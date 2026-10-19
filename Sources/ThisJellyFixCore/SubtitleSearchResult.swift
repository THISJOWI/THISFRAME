import Foundation

/// A subtitle the user can pick, whatever provider it came from.
///
/// The player's search sheet lists these, so the server's own providers and
/// the ones the app queries itself live in the same list without the sheet
/// having to care where a row came from.
public struct SubtitleSearchResult: Identifiable, Sendable, Equatable {
    /// How the file is obtained when the user taps the row.
    public enum Handle: Sendable, Equatable {
        /// The Jellyfin server knows how to fetch it — it already runs the
        /// provider and stores the file next to the video.
        case server(subtitleId: String)
        /// The app has to fetch it from the provider and hand it to the
        /// server, which then serves it like any other external subtitle.
        case clientSide(provider: SubtitleProviderID, subtitleId: String, fileId: Int?)
    }

    /// Stable id for the row (provider + provider-side id).
    public let id: String
    /// Name of the provider that produced the row.
    public let providerName: String
    /// Release / file name reported by the provider.
    public let name: String
    /// Subtitle format (`srt`, `vtt`, `ass`…). nil when unknown.
    public let format: String?
    /// ISO 639 code of the subtitle language.
    public let languageCode: String?
    /// How many times the subtitle was downloaded.
    public let downloadCount: Int?
    /// Community rating, 0…5.
    public let communityRating: Float?
    /// True when the provider matched the exact media file.
    public let isHashMatch: Bool
    /// True when the subtitle was machine translated.
    public let isMachineTranslated: Bool
    /// How to obtain the file.
    public let handle: Handle

    public init(
        id: String,
        providerName: String,
        name: String,
        format: String? = nil,
        languageCode: String? = nil,
        downloadCount: Int? = nil,
        communityRating: Float? = nil,
        isHashMatch: Bool = false,
        isMachineTranslated: Bool = false,
        handle: Handle
    ) {
        self.id = id
        self.providerName = providerName
        self.name = name
        self.format = format
        self.languageCode = languageCode
        self.downloadCount = downloadCount
        self.communityRating = communityRating
        self.isHashMatch = isHashMatch
        self.isMachineTranslated = isMachineTranslated
        self.handle = handle
    }

    /// Row title: what the subtitle is, plus where it came from.
    public var displayName: String {
        var parts: [String] = []
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(title.isEmpty ? (format?.uppercased() ?? "Subtítulo") : title)
        parts.append("· \(providerName)")
        if let communityRating {
            parts.append(String(format: "· ★%.1f", communityRating))
        }
        return parts.joined(separator: " ")
    }
}

public extension SubtitleSearchResult {
    /// Adapt a server result (`GET /Items/{id}/RemoteSearch/Subtitles/…`).
    init(server info: RemoteSubtitleInfo) {
        let provider = info.providerName.flatMap { $0.isEmpty ? nil : $0 } ?? "Servidor"
        let title = info.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? info.format?.uppercased()
            ?? "Subtítulo"
        self.init(
            id: "server:\(info.id)",
            providerName: provider,
            name: title,
            format: info.format,
            languageCode: info.threeLetterISOLanguageName,
            downloadCount: info.downloadCount,
            communityRating: info.communityRating,
            isHashMatch: info.isHashMatch ?? false,
            handle: .server(subtitleId: info.id)
        )
    }
}
