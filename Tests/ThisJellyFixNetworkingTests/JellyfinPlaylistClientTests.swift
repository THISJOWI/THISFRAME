import XCTest
@testable import ThisJellyFixNetworking
@testable import ThisJellyFixCore

final class JellyfinPlaylistClientTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    func testFetchPlaylistsAsksForPlaylistItems() async throws {
        let session = MockNetworkSession(data: """
        {"Items":[{"Id":"p1","Name":"Fin de semana","Type":"Playlist","ChildCount":4}]}
        """.data(using: .utf8)!, statusCode: 200)

        let playlists = try await JellyfinPlaylistClient(session: session).fetchPlaylists(
            userId: "u1", serverURL: server, token: "tok"
        )

        XCTAssertEqual(playlists.first?.name, "Fin de semana")
        XCTAssertEqual(playlists.first?.childCount, 4)
        let request = try XCTUnwrap(session.capturedRequest)
        let query = try XCTUnwrap(request.url?.query)
        XCTAssertTrue(query.contains("IncludeItemTypes=Playlist"))
        XCTAssertTrue(query.contains("Recursive=true"))
    }

    func testFetchCollectionsUsesBoxSetType() async throws {
        let session = MockNetworkSession(data: """
        {"Items":[{"Id":"c1","Name":"Saga","Type":"BoxSet"}]}
        """.data(using: .utf8)!, statusCode: 200)

        let collections = try await JellyfinPlaylistClient(session: session).fetchCollections(
            userId: "u1", serverURL: server, token: "tok"
        )

        XCTAssertEqual(collections.first?.type, "BoxSet")
        let query = try XCTUnwrap(session.capturedRequest?.url?.query)
        XCTAssertTrue(query.contains("IncludeItemTypes=BoxSet"))
    }

    func testPlaylistItemsKeepTheirEntryId() async throws {
        let session = MockNetworkSession(data: """
        {"Items":[{"Id":"m1","Name":"Inception","Type":"Movie","PlaylistItemId":"e1"}]}
        """.data(using: .utf8)!, statusCode: 200)

        let items = try await JellyfinPlaylistClient(session: session).fetchPlaylistItems(
            playlistId: "p1", userId: "u1", serverURL: server, token: "tok"
        )

        XCTAssertEqual(items.first?.id, "m1")
        XCTAssertEqual(items.first?.playlistItemId, "e1")
    }

    func testCreatePlaylistPostsNameDescriptionAndItems() async throws {
        let session = MockNetworkSession(data: """
        {"Id":"new-playlist"}
        """.data(using: .utf8)!, statusCode: 200)

        let id = try await JellyfinPlaylistClient(session: session).createPlaylist(
            name: "Ciencia ficción",
            description: "Pendientes",
            itemIds: ["m1", "m2"],
            userId: "u1",
            serverURL: server,
            token: "tok"
        )

        XCTAssertEqual(id, "new-playlist")
        let request = try XCTUnwrap(session.capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/Playlists")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["Name"] as? String, "Ciencia ficción")
        XCTAssertEqual(body?["Description"] as? String, "Pendientes")
        XCTAssertEqual(body?["Ids"] as? [String], ["m1", "m2"])
        XCTAssertEqual(body?["UserId"] as? String, "u1")
    }

    func testAddAndRemoveUseTheRightQueryParameters() async throws {
        let addSession = MockNetworkSession(data: Data(), statusCode: 204)
        try await JellyfinPlaylistClient(session: addSession).addItems(
            playlistId: "p1", itemIds: ["m1", "m2"], userId: "u1", serverURL: server, token: "tok"
        )
        let addRequest = try XCTUnwrap(addSession.capturedRequest)
        XCTAssertEqual(addRequest.httpMethod, "POST")
        XCTAssertEqual(addRequest.url?.path, "/Playlists/p1/Items")
        let addQuery = try XCTUnwrap(addRequest.url?.query)
        XCTAssertTrue(addQuery.contains("ids=m1,m2"))
        XCTAssertTrue(addQuery.contains("userId=u1"))

        let removeSession = MockNetworkSession(data: Data(), statusCode: 204)
        try await JellyfinPlaylistClient(session: removeSession).removeItems(
            playlistId: "p1", entryIds: ["e1"], serverURL: server, token: "tok"
        )
        let removeRequest = try XCTUnwrap(removeSession.capturedRequest)
        XCTAssertEqual(removeRequest.httpMethod, "DELETE")
        XCTAssertEqual(removeRequest.url?.path, "/Playlists/p1/Items")
        let removeQuery = try XCTUnwrap(removeRequest.url?.query)
        XCTAssertTrue(removeQuery.contains("entryIds=e1"))
    }

    func testForbiddenSurfacesAsForbidden() async throws {
        let session = MockNetworkSession(data: Data(), statusCode: 403)

        do {
            try await JellyfinPlaylistClient(session: session).deletePlaylist(
                playlistId: "p1", serverURL: server, token: "tok"
            )
            XCTFail("Expected forbidden")
        } catch let error as LibraryError {
            XCTAssertEqual(error, .forbidden)
        }
    }
}

// MARK: - Mock

private final class MockNetworkSession: JellyfinNetworkSession, @unchecked Sendable {
    let mockData: Data
    let mockStatusCode: Int
    private(set) var capturedRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.mockData = data
        self.mockStatusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (mockData, response)
    }
}
