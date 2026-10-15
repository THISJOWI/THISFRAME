import Foundation

/// Metadata-driven subtitle ranking — no content sniffing.
///
/// Auto-selection used to pick the FIRST track matching the preferred
/// language in server order. When an item carries several same-language
/// tracks (full dialogue + SDH/CC + forced + commentary sidecars), that
/// first match is arbitrary: users got background-description tracks or
/// forced-only tracks instead of the dialogue track.
///
/// Ranking uses ONLY server metadata (`Language`, `IsForced`,
/// `IsHearingImpaired`, `IsDefault`, `Index`):
/// 1. Language must match the preference (via `LanguagePreferences.matches`).
/// 2. Prefer full tracks over forced-only ones (forced carries a subset).
/// 3. Prefer non-SDH over SDH/CC when both exist (SDH adds
///    sound/background descriptions on top of the same dialogue).
/// 4. Prefer the server's `IsDefault`, then lowest `Index` (stable).
/// No track is ever filtered by its TEXT — every candidate stays selectable
/// manually; this only orders the AUTOMATIC pick.
public enum SubtitleSelection {
    /// Index into `streams` of the best automatic pick for `preferred`
    /// language, or nil when nothing matches (caller leaves subs untouched).
    public static func bestStreamIndex(
        in streams: [MediaStream],
        preferred: String?
    ) -> Int? {
        guard let preferred, !preferred.isEmpty else { return nil }
        var best: Int?
        var bestScore: Score?
        for (i, stream) in streams.enumerated() {
            guard stream.type == "Subtitle" else { continue }
            guard LanguagePreferences.matches(preferred: preferred, trackLanguage: stream.language) else { continue }
            let score = Score(stream: stream, position: i)
            if bestScore == nil || score < bestScore! {
                bestScore = score
                best = i
            }
        }
        return best
    }

    /// Rank key: smaller wins. Tuple order = priority order above.
    struct Score: Comparable, Equatable {
        let forcedPenalty: Int
        let sdhPenalty: Int
        let defaultBonus: Int
        let position: Int

        init(stream: MediaStream, position: Int) {
            forcedPenalty = (stream.isForced == true) ? 1 : 0
            sdhPenalty = (stream.isHearingImpaired == true) ? 1 : 0
            // IsDefault=true sorts before unset/false.
            defaultBonus = (stream.isDefault == true) ? 0 : 1
            self.position = position
        }

        static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.forcedPenalty != rhs.forcedPenalty { return lhs.forcedPenalty < rhs.forcedPenalty }
            if lhs.sdhPenalty != rhs.sdhPenalty { return lhs.sdhPenalty < rhs.sdhPenalty }
            if lhs.defaultBonus != rhs.defaultBonus { return lhs.defaultBonus < rhs.defaultBonus }
            return lhs.position < rhs.position
        }
    }
}
