import Foundation

/// Verifiable novelty of a library item. Every case is backed by server
/// timestamps — the app never guesses a badge from "unwatched" alone.
public enum MediaNovelty: Equatable, Sendable {
    /// Episode incorporated into the library during the current calendar day.
    case newEpisodeToday
    /// Established series that gained a genuinely new season (verified by
    /// comparing the series creation date against its seasons' dates).
    case newSeason
    /// Item incorporated within the novelty window (last 30 days).
    case recentlyAdded
}

/// Central classifier for novelty badges and hero/row prioritisation.
///
/// Verification strategy (no change-history endpoint exists):
/// - "Nueva temporada" requires the SERIES to be older than the window AND at
///   least one of its seasons to be younger than the window. A bulk import
///   creates series + seasons at the same instant, so it can never satisfy
///   both conditions and correctly degrades to "Recién añadido".
/// - "Nuevo hoy" requires the episode's `DateCreated` to fall on the current
///   calendar day (the user's timezone), distinguishing it from older
///   incorporations. `PremiereDate` is intentionally NOT used here: an old
///   episode swept into the library today is "added today", not a premiere.
/// - Anything else inside the 30-day window is "Recién añadido"; anything
///   older (or missing a date) gets no badge at all.
public struct NoveltyClassifier: Sendable {
    /// 30-day novelty window, per product decision.
    public static let window: TimeInterval = 30 * 24 * 60 * 60

    public let now: Date
    public let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    /// Badge for an item, given whether a new season was independently
    /// verified for this series (see `hasVerifiedNewSeason`).
    public func novelty(
        for item: JellyfinMediaItem,
        verifiedNewSeason: Bool = false
    ) -> MediaNovelty? {
        let created = JellyfinDate.parse(item.dateCreated)

        if item.type == "Episode", let created,
           calendar.isDate(created, inSameDayAs: now) {
            return .newEpisodeToday
        }

        if item.type == "Series", verifiedNewSeason {
            return .newSeason
        }

        if let created, now.timeIntervalSince(created) <= Self.window, created <= now {
            return .recentlyAdded
        }

        // No verifiable date → no badge (never invent novelty).
        return nil
    }

    /// "Nueva temporada" verification: the series must predate the window
    /// (established show) while at least one season was created inside it.
    /// Seasons without dates (Fields not answered) fail verification — the
    /// badge is withheld rather than guessed.
    public func hasVerifiedNewSeason(
        seriesDateCreated raw: String?,
        seasons: [JellyfinSeason]
    ) -> Bool {
        guard let seriesCreated = JellyfinDate.parse(raw),
              now.timeIntervalSince(seriesCreated) > Self.window
        else { return false }

        return seasons.contains { season in
            guard let seasonCreated = JellyfinDate.parse(season.dateCreated) else {
                return false
            }
            return now.timeIntervalSince(seasonCreated) <= Self.window
                && seasonCreated <= now
        }
    }

    /// True when the item is a plausible new-season candidate worth a seasons
    /// fetch: a series last touched inside the window (folder-level
    /// `DateLastMediaAdded`) but created outside it. Cheap pre-filter that
    /// keeps the per-series verification requests bounded.
    public func isSeasonCandidate(_ item: JellyfinMediaItem) -> Bool {
        guard item.type == "Series",
              let created = JellyfinDate.parse(item.dateCreated),
              now.timeIntervalSince(created) > Self.window
        else { return false }

        // No DateLastMediaAdded → cannot rule it in cheaply; skip.
        guard let lastAdded = JellyfinDate.parse(item.dateLastMediaAdded) else {
            return false
        }
        return now.timeIntervalSince(lastAdded) <= Self.window && lastAdded <= now
    }
}
