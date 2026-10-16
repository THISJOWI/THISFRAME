import Foundation
import ThisJellyFixCore

/// Resultado de planificar la reproducción de un item: qué fuente servir y
/// qué audio pedir al servidor.
public struct PlaybackPlan: Sendable, Equatable {
    public let source: MediaSource
    public let playSessionId: String?
    /// Audio SERVIDO (`MediaStream.index`): el pedido o el default del
    /// servidor. La VM lo usa para mapear engine↔servidor en el picker.
    public let audioServerIndex: Int?

    public init(
        source: MediaSource,
        playSessionId: String?,
        audioServerIndex: Int?
    ) {
        self.source = source
        self.playSessionId = playSessionId
        self.audioServerIndex = audioServerIndex
    }
}

/// Resuelve el plan de reproducción con 1-2 llamadas a `PlaybackInfo`:
///
/// 1. Pide el plan base (sin índices).
/// 2. Pre-resuelve el audio preferido (`AudioStreamIndex`).
/// 3. Solo si el preferido difiere del default, repite la llamada con el
///    índice: el servidor sirve ESE audio en remux/transcode. Sin mismatch,
///    un solo roundtrip (cero cambios respecto a antes).
///
/// INVARIANTE (dobles): los subtítulos SIEMPRE se piden con -1 (nada
/// mux/quemado). El overlay cliente es el único renderer en pantalla
/// completa; la pista nativa queda reservada a PiP. Muxear el sub en el
/// remux hacía que AVPlayer lo autoseleccionara al abrir, por encima de
/// nuestros apagados.
public func resolvePlaybackPlan(
    client: JellyfinPlaybackClient = JellyfinPlaybackClient(),
    userId: String,
    serverURL: URL,
    token: String,
    itemId: String,
    quality: StreamQuality
) async throws -> PlaybackPlan {
    let base = try await client.fetchPlaybackInfo(
        userId: userId,
        serverURL: serverURL,
        token: token,
        itemId: itemId,
        deviceProfile: .avPlayer.capped(to: quality.maxBitrate),
        maxStreamingBitrate: quality.maxBitrate
    )
    guard let baseSource = base.mediaSources.first else {
        throw LibraryError.invalidResponse
    }

    let prefs = LanguagePreferences.current()
    let preferredAudio = prefs.preferredAudio ?? LanguagePreferences.systemDefault

    let audioIdx = PlaybackStreamPicker.audioIndex(in: baseSource.mediaStreams, preferred: preferredAudio)

    guard let audioIdx else {
        // Sin mismatch: el plan base ya sirve lo correcto.
        return PlaybackPlan(
            source: baseSource,
            playSessionId: base.playSessionId,
            audioServerIndex: PlaybackStreamPicker.defaultAudioIndex(in: baseSource.mediaStreams)
        )
    }

    TJFLog("plan: pre-resolving audio=\(audioIdx) item=\(itemId)")
    let refined = try await client.fetchPlaybackInfo(
        userId: userId,
        serverURL: serverURL,
        token: token,
        itemId: itemId,
        deviceProfile: .avPlayer.capped(to: quality.maxBitrate),
        maxStreamingBitrate: quality.maxBitrate,
        subtitleStreamIndex: -1,
        audioStreamIndex: audioIdx
    )
    guard let refinedSource = refined.mediaSources.first else {
        // El refinado falló en forma: el plan base sigue siendo reproducible.
        TJFLog("plan: refined answer sourceless — falling back to base plan")
        return PlaybackPlan(
            source: baseSource,
            playSessionId: base.playSessionId,
            audioServerIndex: audioIdx
        )
    }
    return PlaybackPlan(
        source: refinedSource,
        playSessionId: refined.playSessionId,
        audioServerIndex: audioIdx
    )
}
