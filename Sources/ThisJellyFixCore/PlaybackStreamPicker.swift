import Foundation

/// Pre-resolución de índices de stream para `PlaybackInfo` — metadata only.
///
/// El servidor sirve UN solo audio en remux/transcode y muxea subtítulos en
/// el remux solo si se le pide: sin `AudioStreamIndex`/`SubtitleStreamIndex`
/// los alternativos "desaparecen" del lado cliente aunque el servidor los
/// liste. Estas funciones deciden QUÉ pedir; nunca ocultan pistas.
public enum PlaybackStreamPicker {
    /// Codecs bitmap: pedir su índice quemaría (`Encode`) el sub en el vídeo.
    /// Se resuelven solo pistas de texto (las que el overlay renderiza).
    public static let bitmapCodecs: Set<String> = [
        "pgssub", "hdmv_pgs_subtitle", "dvdsub", "vobsub", "dvb_subtitle", "xsub",
    ]

    /// Índice SERVIDOR (`MediaStream.index`) del mejor subtítulo de texto
    /// para `preferred`, o nil (el llamante envía -1: nada mux/quemado).
    /// Reutiliza el ranking por metadatos de `SubtitleSelection`.
    public static func subtitleIndex(
        in streams: [MediaStream],
        preferred: String?
    ) -> Int? {
        guard let preferred, !preferred.isEmpty else { return nil }
        let text = streams.filter { stream in
            guard stream.type == "Subtitle" else { return false }
            return !bitmapCodecs.contains((stream.codec ?? "").lowercased())
        }
        guard let pos = SubtitleSelection.bestStreamIndex(in: text, preferred: preferred) else { return nil }
        return text[pos].index
    }

    /// Índice SERVIDOR del audio preferido cuando NO es el que el servidor
    /// serviría por defecto, o nil (no hace falta pedir nada: evita un
    /// segundo roundtrip cuando el default ya coincide).
    public static func audioIndex(
        in streams: [MediaStream],
        preferred: String?
    ) -> Int? {
        guard let preferred, !preferred.isEmpty else { return nil }
        let audios = streams.filter { $0.type == "Audio" }
        guard !audios.isEmpty else { return nil }
        var best: MediaStream?
        var bestIsDefault = false
        for stream in audios {
            guard LanguagePreferences.matches(preferred: preferred, trackLanguage: stream.language) else { continue }
            let flagged = stream.isDefault == true
            // Primer match gana, salvo que otro match sea el default.
            if best == nil || (flagged && !bestIsDefault) {
                best = stream
                bestIsDefault = flagged
            }
        }
        guard let best, let idx = best.index else { return nil }
        // Ya es el default del servidor: pedirlo sería redundante.
        if idx == defaultAudioIndex(in: streams) { return nil }
        return idx
    }

    /// Índice SERVIDOR del audio que el servidor sirve sin pedir nada:
    /// el marcado `IsDefault`, o el primero.
    public static func defaultAudioIndex(in streams: [MediaStream]) -> Int? {
        let audios = streams.filter { $0.type == "Audio" }
        if let flagged = audios.first(where: { $0.isDefault == true }) {
            return flagged.index
        }
        return audios.first?.index
    }
}
