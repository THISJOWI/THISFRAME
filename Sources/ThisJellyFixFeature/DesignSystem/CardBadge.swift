import Foundation
import ThisJellyFixCore

/// Overlay badge shown on top of a media card (Netflix-style).
enum CardBadge: Equatable {
    /// Accent "Nuevo hoy" flag — episode incorporated today (verified).
    case newEpisodeToday
    /// Red "Nueva temporada" flag — verified season addition.
    case newSeason
    /// Neutral "Recién añadido" flag — inside the 30-day novelty window.
    case recentlyAdded
    /// White "Siguiente episodio" flag, optionally with the air day below.
    case nextEpisode(day: String?)
}

extension CardBadge {
    /// Badge for a card, given the resume-item ids (currently-watching) and
    /// the ids whose "Nueva temporada" was independently verified by the
    /// model (season-date comparison — see `NoveltyClassifier`).
    ///
    /// Precedence: resume > verified new season > today's episode > recently
    /// added. Every novelty case is date-backed; an item without a verifiable
    /// date gets no badge at all.
    static func badge(
        for item: JellyfinMediaItem,
        resumeItems: Set<String>,
        verifiedNewSeasonIDs: Set<String> = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CardBadge? {
        if resumeItems.contains(item.id) {
            return .nextEpisode(day: nil)
        }
        let classifier = NoveltyClassifier(now: now, calendar: calendar)
        switch classifier.novelty(
            for: item,
            verifiedNewSeason: verifiedNewSeasonIDs.contains(item.id)
        ) {
        case .newSeason:
            return .newSeason
        case .newEpisodeToday:
            return .newEpisodeToday
        case .recentlyAdded:
            return .recentlyAdded
        case nil:
            return nil
        }
    }
}
