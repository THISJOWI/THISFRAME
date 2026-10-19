import Foundation
import ThisJellyFixCore

public enum SubtitleSearchError: LocalizedError, Equatable {
    case invalidLanguage
    case serverError(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLanguage: "Indica un idioma para buscar (p. ej. «es» o «spa»)."
        case .serverError(let code): "La búsqueda falló (HTTP \(code))."
        }
    }
}

/// Remote subtitle search + download (player subtitle sheet).
///
/// Verified against the Jellyfin stable OpenAPI — NOT guessed:
/// - `GET /Items/{itemId}/RemoteSearch/Subtitles/{language}` → `[RemoteSubtitleInfo]`
///   (empty when the server has no subtitle provider configured).
/// - `POST /Items/{itemId}/RemoteSearch/Subtitles/{subtitleId}` → 204, stores
///   the file server-side as a new external subtitle of the item.
/// - `POST /Videos/{itemId}/Subtitles` → 204, uploads a subtitle file the
///   app fetched itself (`UploadSubtitleDto`: Data/Language/Format/
///   IsForced/IsHearingImpaired). This is how a provider the app queries
///   itself lands in the server, and from there in the player, without
///   touching the playback path.
///
/// Auth follows the house pattern (Authorization header with the token).
/// No credentials are stored here — the caller passes the in-memory token.
public struct JellyfinSubtitleClient: Sendable {
    private let session: any JellyfinNetworkSession

    public init(session: any JellyfinNetworkSession = URLSession.shared) {
        self.session = session
    }

    /// Search the server's subtitle providers for `itemId` in `language`.
    public func searchRemoteSubtitles(
        serverURL: URL,
        token: String,
        itemId: String,
        language: String
    ) async throws -> [RemoteSubtitleInfo] {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard !lang.isEmpty else { throw SubtitleSearchError.invalidLanguage }
        let url = serverURL.appendingPathComponent("Items/\(itemId)/RemoteSearch/Subtitles/\(lang)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(authHeader(token: token), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibraryError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw LibraryError.unauthorized
        default: throw SubtitleSearchError.serverError(http.statusCode)
        }
        let decoded = try JSONDecoder().decode([RemoteSubtitleInfo].self, from: data)
        TJFLog("subsearch: item=\(itemId) lang=\(lang) results=\(decoded.count)")
        return decoded
    }

    /// Download one remote result server-side. Returns on 2xx; the caller
    /// then refreshes the item's subtitle list to pick the new file up.
    public func downloadRemoteSubtitle(
        serverURL: URL,
        token: String,
        itemId: String,
        subtitleId: String
    ) async throws {
        let sid = subtitleId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subtitleId
        let url = serverURL.appendingPathComponent("Items/\(itemId)/RemoteSearch/Subtitles/\(sid)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(authHeader(token: token), forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibraryError.invalidResponse }
        switch http.statusCode {
        case 200...299:
            TJFLog("subsearch: downloaded subtitleId=\(subtitleId) item=\(itemId)")
        case 401: throw LibraryError.unauthorized
        default: throw SubtitleSearchError.serverError(http.statusCode)
        }
    }

    /// Hand a subtitle file the app downloaded itself to the server.
    ///
    /// The server stores it as an external subtitle of the item, exactly as
    /// it does with a file its own providers fetched — so the player picks
    /// it up through the usual "refresh the stream list" path.
    ///
    /// - Parameters:
    ///   - data: the subtitle text (SRT/VTT/ASS…).
    ///   - language: ISO 639 code of the subtitle (`spa`, `eng`…).
    ///   - format: subtitle format the server should store (`srt`, `vtt`…).
    public func uploadExternalSubtitle(
        serverURL: URL,
        token: String,
        itemId: String,
        data: String,
        language: String,
        format: String,
        isForced: Bool = false,
        isHearingImpaired: Bool = false
    ) async throws {
        let url = serverURL.appendingPathComponent("Videos/\(itemId)/Subtitles")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(authHeader(token: token), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = UploadSubtitlePayload(
            language: language,
            format: format,
            isForced: isForced,
            isHearingImpaired: isHearingImpaired,
            data: data
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LibraryError.invalidResponse }
        switch http.statusCode {
        case 200...299:
            TJFLog("subsearch: uploaded external subtitle item=\(itemId) format=\(format)")
        case 401: throw LibraryError.unauthorized
        default: throw SubtitleSearchError.serverError(http.statusCode)
        }
    }

    private func authHeader(token: String) -> String {
        "MediaBrowser Client=\"thisjellyfix\", Device=\"\(deviceOS)\", DeviceId=\"\(DeviceIdentifier().current())\", Version=\"0.1\", Token=\"\(token)\""
    }

    private var deviceOS: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "unknown"
        #endif
    }
}

/// Body of `POST /Videos/{itemId}/Subtitles`.
///
/// The server's `UploadSubtitleDto` has `additionalProperties: false` and
/// requires all five fields, so the payload is spelled out exactly.
private struct UploadSubtitlePayload: Encodable {
    let language: String
    let format: String
    let isForced: Bool
    let isHearingImpaired: Bool
    let data: String

    enum CodingKeys: String, CodingKey {
        case language = "Language"
        case format = "Format"
        case isForced = "IsForced"
        case isHearingImpaired = "IsHearingImpaired"
        case data = "Data"
    }
}
