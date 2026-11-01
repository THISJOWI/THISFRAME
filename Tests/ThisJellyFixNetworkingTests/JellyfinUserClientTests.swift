import XCTest
@testable import ThisJellyFixNetworking
@testable import ThisJellyFixCore

final class JellyfinUserClientTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    func testFetchProfileReadsPolicyAndAvatarTag() async throws {
        let session = MockNetworkSession(responses: [(
            """
            {"Id":"u1","Name":"Joel","PrimaryImageTag":"abc",
             "Policy":{"IsAdministrator":true},
             "LastLoginDate":"2026-10-30T20:00:00Z","HasPassword":true}
            """.data(using: .utf8)!,
            200
        )])

        let profile = try await JellyfinUserClient(session: session).fetchProfile(
            userId: "u1", serverURL: server, token: "tok"
        )

        XCTAssertEqual(profile.name, "Joel")
        XCTAssertEqual(profile.primaryImageTag, "abc")
        XCTAssertTrue(profile.isAdministrator)
        XCTAssertEqual(profile.lastLoginDate, "2026-10-30T20:00:00Z")
        XCTAssertEqual(profile.hasPassword, true)
    }

    func testMissingPolicyMeansNotAdministrator() async throws {
        let session = MockNetworkSession(responses: [(
            #"{"Id":"u1","Name":"Joel"}"#.data(using: .utf8)!, 200
        )])

        let profile = try await JellyfinUserClient(session: session).fetchProfile(
            userId: "u1", serverURL: server, token: "tok"
        )

        XCTAssertFalse(profile.isAdministrator)
    }

    func testUploadAvatarPostsRawImageWithContentType() async throws {
        let session = MockNetworkSession(responses: [(Data(), 204)])
        let image = Data([0xFF, 0xD8, 0xFF, 0xE0])

        try await JellyfinUserClient(session: session).uploadAvatar(
            userId: "u1",
            serverURL: server,
            token: "tok",
            imageData: image,
            contentType: "image/jpeg"
        )

        let request = try XCTUnwrap(session.capturedRequests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/Users/u1/Images/Primary")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(request.httpBody, image)
    }

    /// The rename round-trips the full user record so no other field is wiped.
    func testUpdateNamePreservesTheRestOfTheUserRecord() async throws {
        let session = MockNetworkSession(responses: [
            ("""
            {"Id":"u1","Name":"Old","HasPassword":true,"Policy":{"IsAdministrator":true,"EnableAllFolders":false}}
            """.data(using: .utf8)!, 200),
            (Data(), 204),
        ])

        try await JellyfinUserClient(session: session).updateName(
            userId: "u1", name: "New", serverURL: server, token: "tok"
        )

        XCTAssertEqual(session.capturedRequests.count, 2)
        let post = try XCTUnwrap(session.capturedRequests.last)
        XCTAssertEqual(post.httpMethod, "POST")
        XCTAssertEqual(post.url?.path, "/Users/u1")
        let body = try XCTUnwrap(post.httpBody)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(object["Name"] as? String, "New")
        XCTAssertEqual(object["HasPassword"] as? Bool, true)
        let policy = try XCTUnwrap(object["Policy"] as? [String: Any])
        XCTAssertEqual(policy["EnableAllFolders"] as? Bool, false)
    }

    func testForbiddenRenameSurfacesAsForbidden() async throws {
        let session = MockNetworkSession(responses: [
            (#"{"Id":"u1","Name":"Old"}"#.data(using: .utf8)!, 200),
            (Data(), 403),
        ])

        do {
            try await JellyfinUserClient(session: session).updateName(
                userId: "u1", name: "New", serverURL: server, token: "tok"
            )
            XCTFail("Expected forbidden")
        } catch let error as LibraryError {
            XCTAssertEqual(error, .forbidden)
        }
    }
}

// MARK: - Mock

private final class MockNetworkSession: JellyfinNetworkSession, @unchecked Sendable {
    private var responses: [(Data, Int)]
    private(set) var capturedRequests: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        let (data, status) = responses.count > 1 ? responses.removeFirst() : responses[0]
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
