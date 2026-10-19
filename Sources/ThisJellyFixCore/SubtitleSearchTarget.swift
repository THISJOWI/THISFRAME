import Foundation

/// What a subtitle provider needs to find subtitles for one item.
///
/// The more precise the fields, the better the match: an Imdb/TMDB id pins
/// the exact title, a title plus season/episode is the fallback for series
/// whose episodes carry no external ids of their own.
public struct SubtitleSearchTarget: Sendable, Equatable {
    /// Movie title, or the series title for an episode.
    public var title: String?
    /// Imdb id, with the `tt` prefix (`tt0111161`).
    public var imdbId: String?
    /// TMDB id.
    public var tmdbId: String?
    /// Season number for episodes.
    public var season: Int?
    /// Episode number for episodes.
    public var episode: Int?
    /// Imdb id of the series an episode belongs to. The provider wants the
    /// *parent* id for an episode, not the episode's own.
    public var parentImdbId: String?
    /// TMDB id of the series an episode belongs to.
    public var parentTmdbId: String?

    public init(
        title: String? = nil,
        imdbId: String? = nil,
        tmdbId: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        parentImdbId: String? = nil,
        parentTmdbId: String? = nil
    ) {
        self.title = title
        self.imdbId = imdbId
        self.tmdbId = tmdbId
        self.season = season
        self.episode = episode
        self.parentImdbId = parentImdbId
        self.parentTmdbId = parentTmdbId
    }

    /// True when there is something to search for.
    public var isEmpty: Bool {
        let hasTitle = !(title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasId = !(imdbId?.isEmpty ?? true)
            || !(tmdbId?.isEmpty ?? true)
            || !(parentImdbId?.isEmpty ?? true)
            || !(parentTmdbId?.isEmpty ?? true)
        return !hasTitle && !hasId
    }
}

public extension JellyfinMediaItem {
    /// Search target for this item.
    ///
    /// An episode is searched by its series title plus season and episode
    /// number — that is what the providers expect when the episode itself
    /// carries no external id.
    func subtitleSearchTarget() -> SubtitleSearchTarget {
        let isEpisode = type == "Episode"
        return SubtitleSearchTarget(
            title: isEpisode ? (seriesName ?? name) : name,
            imdbId: imdbId,
            tmdbId: tmdbId,
            season: isEpisode ? parentIndexNumber : nil,
            episode: isEpisode ? indexNumber : nil
        )
    }
}
