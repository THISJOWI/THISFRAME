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
