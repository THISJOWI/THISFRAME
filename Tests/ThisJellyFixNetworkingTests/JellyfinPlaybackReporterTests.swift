import XCTest
@testable import ThisJellyFixNetworking

/// The stop POST is what marks the item watched on Jellyfin. A momentary
/// network failure must not silently drop it; progress reports stay cheap
/// single-shot.
final class JellyfinPlaybackReporterTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    func testStoppedRetriesTransientNetworkFailures() async {
        let session = FlakyNetworkSession(failuresBeforeSuccess: 1)
        let reporter = JellyfinPlaybackReporter(session: session)

        await reporter.reportStopped(
            userId: "u1",
            serverURL: server,
            token: "tok",
            itemId: "ep-1",
            mediaSourceId: "ep-1",
            positionTicks: 24_000_000_000
        )

        XCTAssertEqual(session.requests.count, 2)
        XCTAssertEqual(session.requests.last?.url?.path, "/Sessions/Playing/Stopped")
        XCTAssertEqual(session.requests.last?.httpMethod, "POST")
    }

    func testProgressDoesNotRetry() async {
        let session = FlakyNetworkSession(failuresBeforeSuccess: 1)
        let reporter = JellyfinPlaybackReporter(session: session)

        await reporter.reportProgress(
            userId: "u1",
            serverURL: server,
            token: "tok",
            itemId: "ep-1",
            mediaSourceId: "ep-1",
            positionTicks: 1_000_000_000,
            isPaused: false
        )

        XCTAssertEqual(session.requests.count, 1)
    }
}

// MARK: - Stub

private final class FlakyNetworkSession: JellyfinNetworkSession, @unchecked Sendable {
    private let lock = NSLock()
    private var failuresBeforeSuccess: Int
    private(set) var requests: [URLRequest] = []

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        let shouldFail = failuresBeforeSuccess > 0
        if shouldFail {
            failuresBeforeSuccess -= 1
        }
        lock.unlock()

        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }
}
