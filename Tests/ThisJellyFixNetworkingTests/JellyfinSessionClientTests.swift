import XCTest
@testable import ThisJellyFixNetworking
@testable import ThisJellyFixCore

final class JellyfinSessionClientTests: XCTestCase {
    private let serverURL = URL(string: "http://localhost:8096")!

    /// A handoff takeover must fire ONLY for another device actively playing
    /// the same item: our own session, other items and paused receivers don't
    /// count (a paused receiver hasn't taken playback over).
    func testTakeoverSourceDetectsOtherDevicePlayingSameItem() async throws {
        let session = MockSessionSession(routes: [
            "Sessions": (200, Self.sessionsJSONData),
        ])

        let client = JellyfinSessionClient(session: session)
        let sessions = try await client.fetchActiveSessions(serverURL: serverURL, token: "tok")

        let takeover = ActiveSessionInfo.takeoverSource(
            in: sessions, ourDeviceId: "device-ours", itemId: "item-1"
        )
        XCTAssertEqual(takeover?.deviceId, "device-tv")
        XCTAssertEqual(takeover?.deviceName, "Salón")
    }

    func testTakeoverSourceIgnoresOwnSessionOtherItemsAndPausedPeers() async throws {
        // Our own device is the only one on item-1 → no takeover.
        let ownSession = try await fetch("""
        [{"DeviceId":"device-ours","DeviceName":"iPhone","UserId":"u1",
          "NowPlayingItem":{"Id":"item-1"},
          "PlayState":{"IsPaused":false,"PlayState":"Playing"}}]
        """)
        XCTAssertNil(ActiveSessionInfo.takeoverSource(
            in: ownSession, ourDeviceId: "device-ours", itemId: "item-1"
        ))

        let sessions = try await fetch(Self.sessionsJSON)
        // Other device, different item → unrelated playback.
        XCTAssertNil(ActiveSessionInfo.takeoverSource(
            in: sessions, ourDeviceId: "device-ours", itemId: "item-99"
        ))
        // Other device on our item but PAUSED → no takeover yet.
        XCTAssertNil(ActiveSessionInfo.takeoverSource(
            in: sessions, ourDeviceId: "device-ours", itemId: "item-3"
        ))
    }

    private func fetch(_ json: String) async throws -> [ActiveSessionInfo] {
        let session = MockSessionSession(routes: [
            "Sessions": (200, json.data(using: .utf8)!),
        ])
        return try await JellyfinSessionClient(session: session)
            .fetchActiveSessions(serverURL: serverURL, token: "tok")
    }

    func testAuthHeaderSent() async throws {
        let session = MockSessionSession(routes: [
            "Sessions": (200, #"[]"#.data(using: .utf8)!),
        ])

        let client = JellyfinSessionClient(session: session)
        _ = try await client.fetchActiveSessions(serverURL: serverURL, token: "secret")

        let auth = session.requests.first?.value(forHTTPHeaderField: "Authorization") ?? ""
        XCTAssertTrue(auth.contains("secret"))
    }

    func testUnauthorizedThrows() async {
        let session = MockSessionSession(routes: [
            "Sessions": (401, Data()),
        ])

        let client = JellyfinSessionClient(session: session)
        do {
            _ = try await client.fetchActiveSessions(serverURL: serverURL, token: "bad")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? LibraryError, .unauthorized)
        }
    }

    /// Other device actively playing item-1 (takeover), our device on item-1,
    /// other device on another item, other device paused on item-3.
    private static let sessionsJSON = """
    [
      {"DeviceId":"device-tv","DeviceName":"Salón","UserId":"u1",
       "NowPlayingItem":{"Id":"item-1"},
       "PlayState":{"IsPaused":false,"PlayState":"Playing"}},
      {"DeviceId":"device-ours","DeviceName":"iPhone","UserId":"u1",
       "NowPlayingItem":{"Id":"item-1"},
       "PlayState":{"IsPaused":false,"PlayState":"Playing"}},
      {"DeviceId":"device-tablet","DeviceName":"iPad","UserId":"u1",
       "NowPlayingItem":{"Id":"item-2"},
       "PlayState":{"IsPaused":false,"PlayState":"Playing"}},
      {"DeviceId":"device-tablet","DeviceName":"iPad","UserId":"u1",
       "NowPlayingItem":{"Id":"item-3"},
       "PlayState":{"IsPaused":true,"PlayState":"Paused"}}
    ]
    """

    private static var sessionsJSONData: Data {
        sessionsJSON.data(using: .utf8)!
    }
}

// MARK: - Mock

/// Routes requests by URL substring → (statusCode, body).
private final class MockSessionSession: JellyfinNetworkSession, @unchecked Sendable {
    let routes: [String: (Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(routes: [String: (Int, Data)]) {
        self.routes = routes
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url?.absoluteString ?? ""
        guard let match = routes.first(where: { url.contains($0.key) }) else {
            XCTFail("unexpected request: \(url)")
            throw URLError(.badURL)
        }
        let (status, body) = match.value
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (body, response)
    }
}
