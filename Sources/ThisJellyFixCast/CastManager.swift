import Foundation
import GoogleCast
import ThisJellyFixCore

/// Coordinador de sesión Cast (iOS).
///
/// Un único objeto observable que expone:
/// - `devices`: qué hay en la red (descubrimiento iniciado a mano, SDK 4.5+).
/// - `state`: `CastSessionState` (Core, puro) — la UI solo lee la máquina.
/// - `mediaState`: posición/duración/estado del receptor (para sincronizar).
///
/// Los listeners del SDK viven en objetos NSObject separados (los protocolos
/// son @objc) y reenvían TODO a este actor principal: así toda la mutación
/// ocurre en un hilo y la UI observa sin bloqueos.
///
/// No conoce Jellyfin ni la UI: recibe una URL ya resuelta y autenticada
/// (preflighteada con `CastStreamPreflight`) y la carga en el receptor.
@MainActor
public final class CastManager: ObservableObject {
    public static let shared = CastManager()

    @Published public private(set) var state = CastSessionState()

    /// Conveniencias para la UI/controlador (la máquina es la fuente).
    public var isConnected: Bool { state.isConnected }
    public var isConnecting: Bool { state.isConnecting }
    @Published public private(set) var devices: [CastDevice] = []
    @Published public private(set) var media = CastMediaState()

    private let sessionListener = SessionListener()
    private let discoveryListener = DiscoveryListener()
    private let mediaListener = MediaListener()

    private init() {
        // Los delegados reenvían al manager vía closures — se enganchan aquí
        // una sola vez; los retain cycles son aceptables en un singleton vivo
        // toda la app (y las closures usan [weak self] vía el hop a MainActor).
        sessionListener.onStarted = { [weak self] name in
            Task { @MainActor [weak self] in self?.handleSessionStarted(name: name) }
        }
        sessionListener.onEnded = { [weak self] error in
            Task { @MainActor [weak self] in self?.handleSessionEnded(error: error) }
        }
        discoveryListener.onDevicesChanged = { [weak self] in
            Task { @MainActor [weak self] in self?.reloadDevices() }
        }
        mediaListener.onStatusChanged = { [weak self] status in
            Task { @MainActor [weak self] in self?.handleMediaStatus(status) }
        }
    }

    // MARK: - Discovery

    /// Arranca el escaneo de la red. El SDK 4.5+ no escanea solo.
    /// Requiere `CastSDK.initialize()` previo (si no, no-op).
    public func startDiscovery() {
        guard CastSDK.isInitialized else {
            TJFLog("cast: startDiscovery ignorado — SDK sin inicializar")
            return
        }
        state.discoveryRequested()
        let dm = GCKCastContext.sharedInstance().discoveryManager
        dm.add(discoveryListener)
        dm.startDiscovery()
        TJFLog("cast: discovery started")
    }

    public func stopDiscovery() {
        guard CastSDK.isInitialized else { return }
        let dm = GCKCastContext.sharedInstance().discoveryManager
        dm.stopDiscovery()
        dm.remove(discoveryListener)
        TJFLog("cast: discovery stopped devices=\(devices.count)")
    }

    private func reloadDevices() {
        guard CastSDK.isInitialized else { return }
        let dm = GCKCastContext.sharedInstance().discoveryManager
        var list: [CastDevice] = []
        for index in 0..<dm.deviceCount {
            let device = dm.device(at: index)
            list.append(
                CastDevice(
                    id: device.deviceID,
                    name: device.friendlyName ?? "Chromecast",
                    isBusy: device.status == .busy
                )
            )
        }
        devices = list
    }

    // MARK: - Sesión

    /// Conecta con un dispositivo de `devices` y mantiene la sesión viva.
    public func connect(to device: CastDevice) {
        guard CastSDK.isInitialized else {
            state.failed(reason: "El SDK de Cast no está inicializado.")
            return
        }
        guard let dmDevice = findDevice(id: device.id) else {
            state.failed(reason: "El dispositivo ya no está disponible.")
            return
        }
        state.deviceSelected(name: device.name)
        let sm = GCKCastContext.sharedInstance().sessionManager
        sm.add(sessionListener)
        if !sm.startSession(with: dmDevice) {
            state.failed(reason: "No se pudo iniciar la sesión con \(device.name).")
        }
    }

    /// Desconexión elegida por el usuario: corta también el media en el receptor.
    public func disconnect() {
        guard CastSDK.isInitialized else { return }
        let sm = GCKCastContext.sharedInstance().sessionManager
        sm.endSessionAndStopCasting(true)
        sm.remove(sessionListener)
        state.sessionEnded()
        media = CastMediaState()
        TJFLog("cast: disconnect by user")
    }

    /// El usuario descartó el fallo mostrado.
    public func acknowledgeFailure() {
        state.acknowledgeFailure()
    }

    private func findDevice(id: String) -> GCKDevice? {
        let dm = GCKCastContext.sharedInstance().discoveryManager
        for index in 0..<dm.deviceCount {
            let device = dm.device(at: index)
            if device.deviceID == id { return device }
        }
        return nil
    }

    private func handleSessionStarted(name: String) {
        // El nombre viene del GCKDevice con el que conectamos; el guard de la
        // máquina descarta eventos de intentos viejos.
        state.sessionStarted(name: name)
        attachMediaListenerIfNeeded()
        TJFLog("cast: session started name=\(name)")
    }

    private func handleSessionEnded(error: String?) {
        let wasConnected = state.isConnected
        if let error {
            // Caída inesperada con sesión viva → failed solo si NO estaba
            // conectado; si lo estaba, la máquina ya cubre el caso.
            state.failed(reason: error)
            if !wasConnected { return }
        }
        state.sessionEnded()
        media = CastMediaState()
        detachMediaListener()
        TJFLog("cast: session ended error=\(error ?? "none")")
    }

    // MARK: - Media

    private var currentCastSession: GCKCastSession? {
        GCKCastContext.sharedInstance().sessionManager.currentSession as? GCKCastSession
    }

    private func attachMediaListenerIfNeeded() {
        guard let client = currentCastSession?.remoteMediaClient else { return }
        client.add(mediaListener)
        // Estado actual por si ya hay media (sesión reanudada).
        if let status = client.mediaStatus { handleMediaStatus(status) }
    }

    private func detachMediaListener() {
        currentCastSession?.remoteMediaClient?.remove(mediaListener)
    }

    /// Carga `url` en el receptor. `startTime` en segundos (reanudación).
    /// `contentType` debe ser el MIME real (HLS: application/x-mpegURL).
    public func load(
        url: URL,
        title: String,
        subtitle: String?,
        artworkURL: URL?,
        contentType: String,
        startTime: Double?
    ) throws {
        guard let client = currentCastSession?.remoteMediaClient else {
            throw CastError.notConnected
        }
        // Última defensa: nunca cargar algo que el receptor no pueda abrir.
        if case .rejected(let reason) = CastStreamPreflight.validateForReceiver(url) {
            throw CastError.unreachable(reason: reason)
        }

        let builder = GCKMediaInformationBuilder(contentURL: url)
        builder.contentType = contentType
        builder.streamType = .buffered

        let metadata = GCKMediaMetadata(metadataType: .generic)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        if let subtitle { metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle) }
        if let artworkURL { metadata.addImage(GCKImage(url: artworkURL, width: 400, height: 600)) }
        builder.metadata = metadata

        let load = GCKMediaLoadRequestDataBuilder()
        load.mediaInformation = builder.build()
        load.autoplay = true
        if let startTime { load.startTime = startTime }

        media = CastMediaState(isLoading: true)
        client.loadMedia(with: load.build())
        TJFLog("cast: load title=\(title) contentType=\(contentType) start=\(startTime.map(Int.init) ?? 0) url=\(url.absoluteString.prefix(80))…")
    }

    public func play() {
        currentCastSession?.remoteMediaClient?.play()
    }

    public func pause() {
        currentCastSession?.remoteMediaClient?.pause()
    }

    public func seek(to seconds: Double) {
        currentCastSession?.remoteMediaClient?.seek(toTimeInterval: seconds)
    }

    public func stopMedia() {
        currentCastSession?.remoteMediaClient?.stop()
    }

    /// Volumen del stream en el receptor [0,1].
    public func setVolume(_ volume: Float) {
        currentCastSession?.remoteMediaClient?.setStreamVolume(min(max(volume, 0), 1))
    }

    private func handleMediaStatus(_ status: GCKMediaStatus?) {
        guard let status else {
            media = CastMediaState()
            return
        }
        let playing: Bool?
        switch status.playerState {
        case .playing: playing = true
        case .paused: playing = false
        case .buffering, .loading: playing = nil
        case .idle: playing = false
        case .unknown: playing = nil
        @unknown default: playing = nil
        }
        media = CastMediaState(
            isPlaying: playing,
            position: status.streamPosition,
            duration: (status.mediaInformation?.streamDuration ?? 0) > 0 ? status.mediaInformation?.streamDuration : nil,
            isLoading: status.playerState == .loading || status.playerState == .buffering,
            ended: status.idleReason == .finished,
            errorMessage: status.idleReason == .error ? "El receptor reportó un error de reproducción." : nil
        )
    }
}

// MARK: - Errores

public enum CastError: Error, LocalizedError {
    case notConnected
    case unreachable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No hay ningún dispositivo Cast conectado."
        case .unreachable(let reason):
            return reason
        }
    }
}

// MARK: - Estado de media publicado

/// Instantánea del estado de reproducción en el receptor. `isPlaying == nil`
/// = transición (loading/buffering): la UI muestra el spinner, no un falso
/// "pausa" (el anti-flicker que ya usa AirPlay).
public struct CastMediaState: Equatable, Sendable {
    public var isPlaying: Bool? = nil
    public var position: Double = 0
    public var duration: Double? = nil
    public var isLoading: Bool = false
    public var ended: Bool = false
    public var errorMessage: String? = nil

    public init(
        isPlaying: Bool? = nil,
        position: Double = 0,
        duration: Double? = nil,
        isLoading: Bool = false,
        ended: Bool = false,
        errorMessage: String? = nil
    ) {
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.isLoading = isLoading
        self.ended = ended
        self.errorMessage = errorMessage
    }
}

// MARK: - Listeners ObjC → closures

/// Sesión: started/ended/error reenviados al manager en MainActor.
private final class SessionListener: NSObject, GCKSessionManagerListener {
    var onStarted: ((String) -> Void)?
    var onEnded: ((String?) -> Void)?

    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        let name = (session as? GCKCastSession)?.device.friendlyName ?? "Chromecast"
        onStarted?(name)
    }

    func sessionManager(
        _ sessionManager: GCKSessionManager,
        didEnd session: GCKSession,
        withError error: (any Error)?
    ) {
        onEnded?(error?.localizedDescription)
    }

    func sessionManager(
        _ sessionManager: GCKSessionManager,
        didFailToStart session: GCKSession,
        withError error: any Error
    ) {
        onEnded?(error.localizedDescription)
    }
}

/// Descubrimiento: cualquier cambio de la lista → recarga completa.
private final class DiscoveryListener: NSObject, GCKDiscoveryManagerListener {
    var onDevicesChanged: (() -> Void)?

    func didUpdateDeviceList(_ discoveryManager: GCKDiscoveryManager) {
        onDevicesChanged?()
    }

    func didInsertDevice(_ device: GCKDevice, at index: UInt) {
        onDevicesChanged?()
    }

    func didRemoveDevice(_ device: GCKDevice, at index: UInt) {
        onDevicesChanged?()
    }
}

/// Media: el receptor avisa de cada cambio de estado (play/pause/seek del
/// mando físico, fin de contenido, errores).
private final class MediaListener: NSObject, GCKRemoteMediaClientListener {
    var onStatusChanged: ((GCKMediaStatus?) -> Void)?

    func remoteMediaClient(_ remoteMediaClient: GCKRemoteMediaClient, didUpdate status: GCKMediaStatus?) {
        onStatusChanged?(status)
    }
}
