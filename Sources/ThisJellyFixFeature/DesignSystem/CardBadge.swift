import Foundation
import ThisJellyFixCore

/// Overlay badge shown on top of a media card (Netflix-style).
enum CardBadge: Equatable {
    /// Solid red "Nueva temporada" flag.
    case newSeason
    /// White "Siguiente episodio" flag, optionally with the air day below.
    case nextEpisode(day: String?)
}

extension CardBadge {
    /// Badge for a card, given the set of resume-item ids (currently-watching).
    ///
    /// Rules: resume wins (the card already says "keep watching" via the
    /// progress bar, but the episode flag reinforces it); unwatched series
    /// get "new season"; everything else stays clean.
    static func badge(for item: JellyfinMediaItem, resumeItems: Set<String>) -> CardBadge? {
        if resumeItems.contains(item.id) {
            return .nextEpisode(day: nil)
        }
        if item.type == "Series", item.userData?.played == false {
            return .newSeason
        }
        return nil
    }
}
