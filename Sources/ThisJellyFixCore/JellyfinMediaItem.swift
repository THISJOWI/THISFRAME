import Foundation

public struct JellyfinMediaItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let type: String
    public let overview: String?
    public let seriesName: String?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let year: Int?
    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let officialRating: String?
    public let communityRating: Double?
    public let genres: [String]?
    public let userData: UserData?
    /// External provider ids the server knows ("Tmdb", "Imdb", "Tvdb", …).
    public let providerIds: [String: String]?
    /// Raw ISO8601 creation date (requires `Fields=DateCreated`). Kept as the
    /// wire string — the server emits fractions of a second that the default
    /// JSON date strategy can't parse; convert with `JellyfinDate.parse`.
    public let dateCreated: String?
    /// Raw ISO8601 "last media added" (requires `Fields=DateLastMediaAdded`,
    /// folders only). Tells when an established series got new episodes.
    public let dateLastMediaAdded: String?
    /// Raw ISO8601 original air/release date (always present in the DTO).
    /// Distinguishes a true premiere from a late incorporation into the library.
    public let premiereDate: String?

    public init(
        id: String,
        name: String,
        type: String,
        overview: String? = nil,
        seriesName: String? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        year: Int? = nil,
        imageTags: [String: String]? = nil,
        backdropImageTags: [String]? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        genres: [String]? = nil,
        userData: UserData? = nil,
        providerIds: [String: String]? = nil,
        dateCreated: String? = nil,
        dateLastMediaAdded: String? = nil,
        premiereDate: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.overview = overview
        self.seriesName = seriesName
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.year = year
        self.imageTags = imageTags
        self.backdropImageTags = backdropImageTags
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.genres = genres
        self.userData = userData
        self.providerIds = providerIds
        self.dateCreated = dateCreated
        self.dateLastMediaAdded = dateLastMediaAdded
        self.premiereDate = premiereDate
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case seriesName = "SeriesName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case year = "Year"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case genres = "Genres"
        case userData = "UserData"
        case providerIds = "ProviderIds"
        case dateCreated = "DateCreated"
        case dateLastMediaAdded = "DateLastMediaAdded"
        case premiereDate = "PremiereDate"
    }

    /// Value for an external provider key, case-insensitive (`Tmdb`/`tmdb`).
    public func providerId(for provider: String) -> String? {
        guard let providerIds else { return nil }
        let wanted = provider.lowercased()
        return providerIds.first { $0.key.lowercased() == wanted }?.value
    }

    public var tmdbId: String? { providerId(for: "Tmdb") }
    public var imdbId: String? { providerId(for: "Imdb") }

    public var hasImage: Bool {
        imageTags?["Primary"] != nil
    }

    /// Percentage watched (0–100). nil if no resume data.
    public var playedPercentage: Double? {
        userData?.playedPercentage
    }

    /// Resume position in seconds. nil if no resume data.
    public var resumePositionSeconds: Double? {
        userData?.resumePositionSeconds
    }

    /// Episode label like "T1 E3" for episodes, nil for movies/series.
    /// Season 0 items use "Especial N" (Jellyfin's convention for specials).
    public var episodeLabel: String? {
        guard type == "Episode" else { return nil }
        // Season 0 = specials (Plex/TVDB convention mirrored by Jellyfin).
        if parentIndexNumber == 0 {
            if let e = indexNumber { return "Especial \(e)" }
            return "Especial"
        }
        if let s = parentIndexNumber, let e = indexNumber {
            return "T\(s) E\(e)"
        }
        if let e = indexNumber {
            return "Ep \(e)"
        }
        return nil
    }

    /// Episode title including its season/episode number for playback UI.
    public var episodeDisplayTitle: String {
        guard let label = episodeLabel else { return name }
        return "\(label) · \(name)"
    }

    /// Display name: series name + episode label for episodes, otherwise just name.
    public var displayName: String {
        if type == "Episode", let seriesName {
            if let label = episodeLabel {
                return "\(seriesName) · \(label)"
            }
            return seriesName
        }
        return name
    }
}

public struct UserData: Codable, Sendable, Equatable, Hashable {
    public let playbackPositionTicks: Int64?
    public let playedPercentage: Double?
    public let isFavorite: Bool?
    public let played: Bool?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
        case isFavorite = "IsFavorite"
        case played = "Played"
    }

    /// Resume position in seconds. nil when the item has never been started.
    public var resumePositionSeconds: Double? {
        playbackPositionTicks.map { Double($0) / 10_000_000.0 }
    }
}

public struct LibraryView: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let collectionType: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
    }
}

// MARK: - Seasons & Episodes

public struct JellyfinSeason: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let indexNumber: Int?
    public let seriesId: String?
    public let imageTags: [String: String]?
    /// Raw ISO8601 creation date (requires `Fields=DateCreated` on the seasons
    /// request). The only verifiable signal for "Nueva temporada".
    public let dateCreated: String?

    public init(
        id: String,
        name: String,
        indexNumber: Int? = nil,
        seriesId: String? = nil,
        imageTags: [String: String]? = nil,
        dateCreated: String? = nil
    ) {
        self.id = id
        self.name = name
        self.indexNumber = indexNumber
        self.seriesId = seriesId
        self.imageTags = imageTags
        self.dateCreated = dateCreated
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case indexNumber = "IndexNumber"
        case seriesId = "SeriesId"
        case imageTags = "ImageTags"
        case dateCreated = "DateCreated"
    }

    public var displayName: String {
        if let indexNumber {
            return "Temporada \(indexNumber)"
        }
        return name
    }
}

public struct JellyfinEpisode: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let overview: String?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let runTimeTicks: Int64?
    public let seriesId: String?
    public let seriesName: String?
    public let seasonName: String?
    public let imageTags: [String: String]?
    public let userData: UserData?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case overview = "Overview"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case runTimeTicks = "RunTimeTicks"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonName = "SeasonName"
        case imageTags = "ImageTags"
        case userData = "UserData"
    }

    /// Resume position in seconds. nil if no resume data.
    public var resumePositionSeconds: Double? {
        userData?.resumePositionSeconds
    }

    public var episodeLabel: String {
        // Season 0 = specials in Jellyfin (Plex/TVDB convention).
        // Show "Especial N" instead of "T0 E1" for a friendlier label.
        if parentIndexNumber == 0 {
            if let e = indexNumber {
                return "Especial \(e)"
            }
            return "Especial"
        }
        if let s = parentIndexNumber, let e = indexNumber {
            return "T\(s) E\(e)"
        }
        if let e = indexNumber {
            return "Episodio \(e)"
        }
        // Fallback when there is truly no numbering metadata.
        return name
    }

    /// Episode label + name combined: "T1 E3 · Nombre del episodio".
    /// Use this wherever you need to show the number and title together.
    /// When no label is derivable (completely unnumbered), just returns `name`.
    public var displayTitle: String {
        let label = episodeLabel
        // Avoid "Nombre · Nombre" when the fallback label IS the name.
        guard label != name else { return name }
        return "\(label) · \(name)"
    }

    public var durationMinutes: Int? {
        guard let runTimeTicks else { return nil }
        return Int(runTimeTicks / 10_000_000 / 60)
    }

    public var hasImage: Bool {
        imageTags?["Primary"] != nil
    }
}
