import Foundation

/// A remote subtitle candidate from the server's providers (OpenSubtitles…).
/// Verified against the Jellyfin stable OpenAPI (`RemoteSubtitleInfo`):
/// `GET /Items/{itemId}/RemoteSearch/Subtitles/{language}` returns these;
/// `POST /Items/{itemId}/RemoteSearch/Subtitles/{subtitleId}` downloads one
/// (204) as a sidecar the player then loads like any external subtitle.
public struct RemoteSubtitleInfo: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let providerName: String?
    public let name: String?
    public let format: String?
    public let author: String?
    public let comment: String?
    public let communityRating: Float?
    public let downloadCount: Int?
    public let isHashMatch: Bool?
    public let threeLetterISOLanguageName: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case providerName = "ProviderName"
        case name = "Name"
        case format = "Format"
        case author = "Author"
        case comment = "Comment"
        case communityRating = "CommunityRating"
        case downloadCount = "DownloadCount"
        case isHashMatch = "IsHashMatch"
        case threeLetterISOLanguageName = "ThreeLetterISOLanguageName"
    }

    public init(
        id: String,
        providerName: String? = nil,
        name: String? = nil,
        format: String? = nil,
        author: String? = nil,
        comment: String? = nil,
        communityRating: Float? = nil,
        downloadCount: Int? = nil,
        isHashMatch: Bool? = nil,
        threeLetterISOLanguageName: String? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.name = name
        self.format = format
        self.author = author
        self.comment = comment
        self.communityRating = communityRating
        self.downloadCount = downloadCount
        self.isHashMatch = isHashMatch
        self.threeLetterISOLanguageName = threeLetterISOLanguageName
    }

    /// One-line display: name + provider + rating when available.
    public var displayName: String {
        var parts: [String] = []
        if let name, !name.isEmpty { parts.append(name) }
        else if let format, !format.isEmpty { parts.append(format.uppercased()) }
        else { parts.append("Subtítulo") }
        if let providerName, !providerName.isEmpty { parts.append("· \(providerName)") }
        if let communityRating { parts.append(String(format: "· ★%.1f", communityRating)) }
        return parts.joined(separator: " ")
    }
}
