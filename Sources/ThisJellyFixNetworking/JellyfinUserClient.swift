import Foundation
import ThisJellyFixCore

/// Profile endpoints that are not covered by the auth or library clients:
/// the full user record, avatar upload and (administrator-only) rename.
public protocol JellyfinUserProviding: Sendable {
    func fetchProfile(userId: String, serverURL: URL, token: String) async throws -> JellyfinUserProfile
    func uploadAvatar(
        userId: String,
        serverURL: URL,
        token: String,
        imageData: Data,
        contentType: String
    ) async throws
    func updateName(
        userId: String,
        name: String,
        serverURL: URL,
        token: String
    ) async throws
}

public struct JellyfinUserClient: JellyfinUserProviding {
    private let session: any JellyfinNetworkSession

    public init(session: any JellyfinNetworkSession = URLSession.shared) {
        self.session = session
    }

    public func fetchProfile(
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> JellyfinUserProfile {
        let data = try await send(
            method: "GET",
            url: serverURL.appendingPathComponent("Users/\(userId)"),
            token: token,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try JSONDecoder().decode(JellyfinUserProfile.self, from: data)
    }

    /// `POST /Users/{userId}/Images/Primary` takes the raw image bytes; the
    /// server derives the format from the Content-Type header.
    public func uploadAvatar(
        userId: String,
        serverURL: URL,
        token: String,
        imageData: Data,
        contentType: String
    ) async throws {
        var request = baseRequest(
            method: "POST",
            url: serverURL.appendingPathComponent("Users/\(userId)/Images/Primary"),
            token: token
        )
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        _ = try await perform(request)
    }

    /// Jellyfin has no "rename me" endpoint: it updates users through
    /// `POST /Users/{id}` with a full UserDto, and requires elevation. The
    /// current record is fetched and posted back with only `Name` changed, so
    /// no other field is wiped. Non-admins get a 403, surfaced as `.forbidden`.
    public func updateName(
        userId: String,
        name: String,
        serverURL: URL,
        token: String
    ) async throws {
        let url = serverURL.appendingPathComponent("Users/\(userId)")
        let current = try await send(
            method: "GET",
            url: url,
            token: token,
            cachePolicy: .reloadIgnoringLocalCacheData
        )

        guard var object = try JSONSerialization.jsonObject(with: current) as? [String: Any] else {
            throw LibraryError.invalidResponse
        }
        object["Name"] = name
        let body = try JSONSerialization.data(withJSONObject: object)

        var request = baseRequest(method: "POST", url: url, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        _ = try await perform(request)
    }

    // MARK: - Helpers

    private func send(
        method: String,
        url: URL,
        token: String,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> Data {
        try await perform(baseRequest(method: method, url: url, token: token, cachePolicy: cachePolicy))
    }

    private func baseRequest(
        method: String,
        url: URL,
        token: String,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(
            "MediaBrowser Client=\"thisjellyfix\", Device=\"\(deviceOS)\", DeviceId=\"\(DeviceIdentifier().current())\", Version=\"0.1\", Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299: return data
        case 401: throw LibraryError.unauthorized
        case 403: throw LibraryError.forbidden
        default: throw LibraryError.serverError(httpResponse.statusCode)
        }
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
