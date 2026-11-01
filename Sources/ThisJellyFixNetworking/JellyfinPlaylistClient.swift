import Foundation
import ThisJellyFixCore

/// Playlists (user-created lists) and BoxSets (server collections).
///
/// Jellyfin stores both as regular items: playlists are `Playlist`, server
/// collections are `BoxSet`. The playlist item list carries a
/// `PlaylistItemId` per entry, which is what removal needs.
public protocol JellyfinPlaylistProviding: Sendable {
    func fetchPlaylists(userId: String, serverURL: URL, token: String) async throws -> [JellyfinMediaItem]
    func fetchCollections(userId: String, serverURL: URL, token: String) async throws -> [JellyfinMediaItem]
    func fetchPlaylistItems(
        playlistId: String,
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> [JellyfinMediaItem]
    func createPlaylist(
        name: String,
        description: String?,
        itemIds: [String],
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> String
    func updatePlaylist(
        playlistId: String,
        name: String,
        description: String?,
        serverURL: URL,
        token: String
    ) async throws
    func deletePlaylist(playlistId: String, serverURL: URL, token: String) async throws
    func addItems(
        playlistId: String,
        itemIds: [String],
        userId: String,
        serverURL: URL,
        token: String
    ) async throws
    func removeItems(
        playlistId: String,
        entryIds: [String],
        serverURL: URL,
        token: String
    ) async throws
}

public struct JellyfinPlaylistClient: JellyfinPlaylistProviding {
    private let session: any JellyfinNetworkSession

    public init(session: any JellyfinNetworkSession = URLSession.shared) {
        self.session = session
    }

    public func fetchPlaylists(
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> [JellyfinMediaItem] {
        try await fetchItems(
            includeTypes: "Playlist",
            userId: userId,
            serverURL: serverURL,
            token: token
        )
    }

    public func fetchCollections(
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> [JellyfinMediaItem] {
        try await fetchItems(
            includeTypes: "BoxSet",
            userId: userId,
            serverURL: serverURL,
            token: token
        )
    }

    public func fetchPlaylistItems(
        playlistId: String,
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> [JellyfinMediaItem] {
        var components = URLComponents(
            url: serverURL.appendingPathComponent("Playlists/\(playlistId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "Fields", value: "Overview,ChildCount"),
            URLQueryItem(name: "Limit", value: "500"),
        ]

        let data = try await send(
            method: "GET",
            url: components.url!,
            token: token,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try JSONDecoder().decode(JellyfinItemsResponse.self, from: data).items
    }

    public func createPlaylist(
        name: String,
        description: String?,
        itemIds: [String],
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> String {
        var body: [String: Any] = [
            "Name": name,
            "UserId": userId,
            "MediaType": "Video",
            "Ids": itemIds,
        ]
        if let description, !description.isEmpty {
            body["Description"] = description
        }

        let data = try await send(
            method: "POST",
            url: serverURL.appendingPathComponent("Playlists"),
            token: token,
            jsonBody: body
        )

        struct CreationResult: Decodable { let id: String
            enum CodingKeys: String, CodingKey { case id = "Id" }
        }
        guard let result = try? JSONDecoder().decode(CreationResult.self, from: data),
              !result.id.isEmpty
        else {
            throw LibraryError.invalidResponse
        }
        return result.id
    }

    public func updatePlaylist(
        playlistId: String,
        name: String,
        description: String?,
        serverURL: URL,
        token: String
    ) async throws {
        var body: [String: Any] = ["Name": name]
        body["Description"] = description ?? ""

        _ = try await send(
            method: "POST",
            url: serverURL.appendingPathComponent("Playlists/\(playlistId)"),
            token: token,
            jsonBody: body
        )
    }

    public func deletePlaylist(
        playlistId: String,
        serverURL: URL,
        token: String
    ) async throws {
        _ = try await send(
            method: "DELETE",
            url: serverURL.appendingPathComponent("Playlists/\(playlistId)"),
            token: token
        )
    }

    public func addItems(
        playlistId: String,
        itemIds: [String],
        userId: String,
        serverURL: URL,
        token: String
    ) async throws {
        guard !itemIds.isEmpty else { return }
        var components = URLComponents(
            url: serverURL.appendingPathComponent("Playlists/\(playlistId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "ids", value: itemIds.joined(separator: ",")),
            URLQueryItem(name: "userId", value: userId),
        ]

        _ = try await send(method: "POST", url: components.url!, token: token)
    }

    public func removeItems(
        playlistId: String,
        entryIds: [String],
        serverURL: URL,
        token: String
    ) async throws {
        guard !entryIds.isEmpty else { return }
        var components = URLComponents(
            url: serverURL.appendingPathComponent("Playlists/\(playlistId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "entryIds", value: entryIds.joined(separator: ",")),
        ]

        _ = try await send(method: "DELETE", url: components.url!, token: token)
    }

    // MARK: - Helpers

    private func fetchItems(
        includeTypes: String,
        userId: String,
        serverURL: URL,
        token: String
    ) async throws -> [JellyfinMediaItem] {
        var components = URLComponents(
            url: serverURL.appendingPathComponent("Users/\(userId)/Items"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: includeTypes),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "ChildCount,Overview"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "Limit", value: "200"),
        ]

        let data = try await send(
            method: "GET",
            url: components.url!,
            token: token,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try JSONDecoder().decode(JellyfinItemsResponse.self, from: data).items
    }

    private func send(
        method: String,
        url: URL,
        token: String,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(
            "MediaBrowser Client=\"thisjellyfix\", Device=\"\(deviceOS)\", DeviceId=\"\(DeviceIdentifier().current())\", Version=\"0.1\", Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

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
