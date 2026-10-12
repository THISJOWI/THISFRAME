import Foundation
import Combine
import GoogleCast
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Capa de salida de reproducción "Cast" (iOS).
///
/// Separa TODO lo Jellyfin/específico del SDK del ViewModel del player:
/// - resuelve la URL de reproducción con el DeviceProfile `.chromecast`
///   (el servidor remuxea/transcodifica lo que el receptor no admite);
/// - preflightea accesibilidad+auth (`CastStreamPreflight`) ANTES de cargar
///   en el Chromecast, donde un 401 es indiagnóstico;
/// - reporta progreso a Jellyfin con la posición REAL del receptor (el
///   servidor sigue marcando vistos y reanudando aunque el motor local
///   esté parado);
/// - expone transporte remoto (play/pause/seek/volumen) y estado.
///
/// Es el "output switcher" que permite añadir en el futuro otras salidas
/// (AirPlay ya existe en el engine; más adelante, qué sea) sin tocar el VM.
@MainActor
public final class CastController: ObservableObject {
    public static let shared = CastController()

    public let manager = CastManager.shared

    /// Posición/duración/estado reportados por el receptor vía listener.
    @Published public private(set) var media = CastMediaState()

    /// true cuando ESTE controller tiene un ítem de Jellyfin en emisión
    /// (la UI del player lo usa para enrutar transporte al receptor).
    @Published public private(set) var isEmitting = false

    /// Contexto del ítem que se está emitiendo — necesario para reportar
    /// progreso al servidor aunque el player view muera.
    private struct CastItemContext {
        let itemId: String
        let mediaSourceId: String
        let userId: String
        let serverURL: URL
        let token: String
    }

    private var itemContext: CastItemContext?
    private var reporter = JellyfinPlaybackReporter()
    private var progressTimer: Timer?
    private var lastReportAt: Date?
    private var reportedPlaying = false

    /// Hook del VM para reflejar el estado remoto en su UI (posición,
    /// duración, play/pause) sin que el VM sondee el manager.
    public var onMediaStatus: ((CastMediaState) -> Void)?

    private init() {
        // Reenvío del estado del manager → este controller (reporte + hook).
        manager.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncFromManager() }
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Sesión (delegado puro a manager)

    public var isConnected: Bool { manager.state.isConnected }
    public var isConnecting: Bool { manager.state.isConnecting }
    public var sessionState: CastSessionState { manager.state }
    public var devices: [CastDevice] { manager.devices }

    public func startDiscovery() { manager.startDiscovery() }
    public func stopDiscovery() { manager.stopDiscovery() }
    public func connect(to device: CastDevice) { manager.connect(to: device) }
    public func acknowledgeFailure() { manager.acknowledgeFailure() }

    /// Desconexión elegida por el usuario: corta el media, reporta el stop
    /// con la posición real y olvida el contexto.
    public func disconnect() {
        reportStopToServer()
        isEmitting = false
        manager.disconnect()
    }

    // MARK: - Carga de contenido

    /// Emite `url` (ya resuelta) al receptor. `playSessionId` enlaza el
    /// reporte con la sesión PlaybackInfo del servidor.
    public func cast(
        url: URL,
        itemId: String,
        mediaSourceId: String,
        userId: String,
        serverURL: URL,
        token: String,
        playSessionId: String?,
        title: String,
        subtitle: String?,
        artworkURL: URL?,
        startTime: Double?
    ) async throws {
        guard manager.isConnected else { throw CastError.notConnected }

        let finalURL: URL
        if case .rejected = CastStreamPreflight.validateForReceiver(url) {
            // Defensa en dos pasos: la URL resuelta no sirve para el
            // receptor (p. ej. sin ApiKey en query) → el servidor, con el
            // perfil chromecast, devuelve un HLS que SÍ es válido.
            finalURL = try await resolveViaServer(
                itemId: itemId, userId: userId, serverURL: serverURL,
                token: token, startTime: startTime
            )
        } else {
            finalURL = url
        }

        try manager.load(
            url: finalURL,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            contentType: CastContentType.detect(from: finalURL),
            startTime: startTime
        )

        itemContext = CastItemContext(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            userId: userId,
            serverURL: serverURL,
            token: token
        )
        reporter.playSessionId = playSessionId
        reportedPlaying = false
        lastReportAt = nil
        isEmitting = true
        startProgressTimer()
        TJFLog("cast: emitiendo item=\(itemId) start=\(startTime.map(Int.init) ?? 0)")
    }

    /// Emite un ítem de Jellyfin resolviendo su stream con el perfil
    /// Chromecast (direct play mp4/h264 o HLS del servidor). Para el botón
    /// "transmitir" del detail sin pasar por el reproductor local.
    public func cast(
        itemId: String,
        mediaSourceId: String?,
        userId: String,
        serverURL: URL,
        token: String,
        title: String,
        subtitle: String?,
        artworkURL: URL?,
        startTime: Double?
    ) async throws {
        let url = try await resolveViaServer(
            itemId: itemId, userId: userId, serverURL: serverURL,
            token: token, startTime: nil
        )
        // mediaSourceId por defecto = itemId (Jellyfin usa el ítem como fuente
        // única cuando no hay variantes).
        try await cast(
            url: url,
            itemId: itemId,
            mediaSourceId: mediaSourceId ?? itemId,
            userId: userId,
            serverURL: serverURL,
            token: token,
            playSessionId: nil,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            startTime: startTime
        )
    }

    /// PlaybackInfo con el perfil `.chromecast` → URL resuelta y autenticada.
    private func resolveViaServer(
        itemId: String,
        userId: String,
        serverURL: URL,
        token: String,
        startTime: Double?
    ) async throws -> URL {
        let info = try await JellyfinPlaybackClient().fetchPlaybackInfo(
            userId: userId,
            serverURL: serverURL,
            token: token,
            itemId: itemId,
            deviceProfile: .chromecast
        )
        guard let source = info.mediaSources.first else {
            throw CastError.unreachable(reason: "El servidor no devolvió ninguna fuente reproduccible.")
        }
        guard let url = StreamURLResolver.playbackURL(
            source: source,
            serverURL: serverURL,
            itemId: itemId,
            token: token
        ) else {
            throw CastError.unreachable(reason: "No se pudo construir la URL de reproducción.")
        }
        if case .rejected(let reason) = CastStreamPreflight.validateForReceiver(url) {
            throw CastError.unreachable(reason: reason)
        }
        return url
    }

    // MARK: - Transporte remoto

    public func play() { manager.play() }
    public func pause() { manager.pause() }
    public func seek(to seconds: Double) {
        manager.seek(to: seconds)
        // El receptor confirma por listener; adelantar la UI evita el
        // "rebote" del scrubber.
        media.position = seconds
        onMediaStatus?(media)
    }
    public func setVolume(_ volume: Float) { manager.setVolume(volume) }

    // MARK: - Sincronización + reporte

    private func syncFromManager() {
        let newMedia = manager.media
        let statusChanged = newMedia != media
        media = newMedia
        guard statusChanged else { return }

        if newMedia.ended {
            TJFLog("cast: contenido terminado en el receptor")
            reportStopToServer()
            isEmitting = false
        }
        onMediaStatus?(newMedia)
    }

    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        // El receiver avisa de cambios de estado, pero NO de la posición en
        // marcha: se muestrea igual que el player local (10 s de reporte).
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func tick() {
        guard itemContext != nil else { return }
        // La posición del receptor avanza sola — refrescar la UI y el
        // lock-screen cada segundo mantiene el "mando" sincronizado.
        onMediaStatus?(media)

        guard media.isPlaying == true else { return }
        if !reportedPlaying {
            reportedPlaying = true
            reportPlayStarted()
        }
        if let last = lastReportAt, Date().timeIntervalSince(last) >= 10 {
            reportProgressToServer()
        }
    }

    private func reportPlayStarted() {
        guard let ctx = itemContext else { return }
        let reporter = reporter
        Task {
            await reporter.reportPlaying(
                userId: ctx.userId, serverURL: ctx.serverURL, token: ctx.token,
                itemId: ctx.itemId, mediaSourceId: ctx.mediaSourceId
            )
        }
    }

    private func reportProgressToServer() {
        guard let ctx = itemContext, media.position > 0 else { return }
        lastReportAt = Date()
        let reporter = reporter
        let ticks = Int64(media.position * 10_000_000) // 100 ns = tick de Jellyfin
        Task {
            await reporter.reportProgress(
                userId: ctx.userId, serverURL: ctx.serverURL, token: ctx.token,
                itemId: ctx.itemId, mediaSourceId: ctx.mediaSourceId,
                positionTicks: ticks, isPaused: media.isPlaying != true
            )
        }
    }

    private func reportStopToServer() {
        guard let ctx = itemContext, media.position > 0 else {
            itemContext = nil
            return
        }
        itemContext = nil
        stopProgressTimer()
        let reporter = reporter
        let ticks = Int64(media.position * 10_000_000)
        Task {
            await reporter.reportStopped(
                userId: ctx.userId, serverURL: ctx.serverURL, token: ctx.token,
                itemId: ctx.itemId, mediaSourceId: ctx.mediaSourceId,
                positionTicks: ticks
            )
        }
    }
}
