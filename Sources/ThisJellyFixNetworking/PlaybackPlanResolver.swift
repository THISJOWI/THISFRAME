import Foundation
import ThisJellyFixCore

/// Resultado de planificar la reproducción de un item: qué fuente servir y
/// qué índices de stream pedir al servidor.
public struct PlaybackPlan: Sendable, Equatable {
    public let source: MediaSource
    public let playSessionId: String?
    /// Audio SERVIDO (`MediaStream.index`): el pedido o el default del
    /// servidor. La VM lo usa para mapear engine↔servidor en el picker.
    public let audioServerIndex: Int?
    /// Subtítulo de texto pre-resuelto (mux en remux / DEFAULT en HLS).
    /// Nil = pedir -1 (nada mux/quemado, como hasta ahora).
    public let subtitleServerIndex: Int?

    public init(
        source: MediaSource,
        playSessionId: String?,
        audioServerIndex: Int?,
        subtitleServerIndex: Int?
    ) {
        self.source = source
        self.playSessionId = playSessionId
        self.audioServerIndex = audioServerIndex
        self.subtitleServerIndex = subtitleServerIndex
    }
}

/// Resuelve el plan de reproducción con 1-2 llamadas a `PlaybackInfo`:
///
/// 1. Pide el plan base (sin índices).
/// 2. Pre-resuelve audio preferido (`AudioStreamIndex`) y subtítulo de
///    texto (`SubtitleStreamIndex`) sobre los streams declarados.
/// 3. Solo si hay algo que pedir, repite la llamada con los índices: el
///    servidor sirve ESE audio en remux/transcode y muxea/marca ese sub.
///    Sin mismatch, un solo roundtrip (cero cambios respecto a antes).
///
/// Pedir un índice bitmap está excluido por construcción
/// (`PlaybackStreamPicker` solo devuelve texto): el burn-in `Encode` nunca
/// se activa por esta vía.
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
    let preferredSubtitles = prefs.preferredSubtitles ?? LanguagePreferences.systemDefault

    let audioIdx = PlaybackStreamPicker.audioIndex(in: baseSource.mediaStreams, preferred: preferredAudio)
    let subIdx = PlaybackStreamPicker.subtitleIndex(in: baseSource.mediaStreams, preferred: preferredSubtitles)

    guard audioIdx != nil || subIdx != nil else {
        // Sin mismatch: el plan base ya sirve lo correcto.
        return PlaybackPlan(
            source: baseSource,
            playSessionId: base.playSessionId,
            audioServerIndex: PlaybackStreamPicker.defaultAudioIndex(in: baseSource.mediaStreams),
            subtitleServerIndex: nil
        )
    }

    TJFLog("plan: pre-resolving audio=\(audioIdx.map(String.init) ?? "-") sub=\(subIdx.map(String.init) ?? "-") item=\(itemId)")
    let refined = try await client.fetchPlaybackInfo(
        userId: userId,
        serverURL: serverURL,
        token: token,
        itemId: itemId,
        deviceProfile: .avPlayer.capped(to: quality.maxBitrate),
        maxStreamingBitrate: quality.maxBitrate,
        subtitleStreamIndex: subIdx ?? -1,
        audioStreamIndex: audioIdx
    )
    guard let refinedSource = refined.mediaSources.first else {
        // El refinado falló en forma: el plan base sigue siendo reproducible.
        TJFLog("plan: refined answer sourceless — falling back to base plan")
        return PlaybackPlan(
            source: baseSource,
            playSessionId: base.playSessionId,
            audioServerIndex: audioIdx ?? PlaybackStreamPicker.defaultAudioIndex(in: baseSource.mediaStreams),
            subtitleServerIndex: nil
        )
    }
    return PlaybackPlan(
        source: refinedSource,
        playSessionId: refined.playSessionId,
        audioServerIndex: audioIdx ?? PlaybackStreamPicker.defaultAudioIndex(in: refinedSource.mediaStreams),
        subtitleServerIndex: subIdx
    )
}
