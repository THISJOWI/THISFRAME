import XCTest
@testable import ThisJellyFixNetworking
import ThisJellyFixCore

final class JellyfinSubtitleClientTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    private let searchJSON = """
    [{"Id":"sub1","ProviderName":"OpenSubtitles","Name":"Movie.spa.srt","Format":"srt","Author":"fan","CommunityRating":4.5,"DownloadCount":120,"IsHashMatch":true,"ThreeLetterISOLanguageName":"spa"}]
    """

    func testSearchHitsVerifiedPathAndDecodes() async throws {
        let session = MockNetworkSession(data: Data(searchJSON.utf8), statusCode: 200)
        let client = JellyfinSubtitleClient(session: session)

        let results = try await client.searchRemoteSubtitles(
            serverURL: server, token: "tok", itemId: "item-1", language: "spa"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "sub1")
        XCTAssertEqual(results[0].providerName, "OpenSubtitles")
        XCTAssertEqual(results[0].isHashMatch, true)
        let request = try XCTUnwrap(session.capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/Items/item-1/RemoteSearch/Subtitles/spa")
    }

    func testSearchEmptyLanguageThrows() async {
        let session = MockNetworkSession(data: Data(), statusCode: 200)
        let client = JellyfinSubtitleClient(session: session)

        await XCTAssertThrowsErrorAsync(
            try await client.searchRemoteSubtitles(serverURL: server, token: "tok", itemId: "item-1", language: "  ")
        ) { error in
            XCTAssertEqual(error as? SubtitleSearchError, .invalidLanguage)
        }
    }

    func testSearchServerErrorMapsStatus() async {
        let session = MockNetworkSession(data: Data(), statusCode: 500)
        let client = JellyfinSubtitleClient(session: session)

        await XCTAssertThrowsErrorAsync(
            try await client.searchRemoteSubtitles(serverURL: server, token: "tok", itemId: "item-1", language: "es")
        ) { error in
            XCTAssertEqual(error as? SubtitleSearchError, .serverError(500))
        }
    }

    func testDownloadPostsVerifiedPath() async throws {
        let session = MockNetworkSession(data: Data(), statusCode: 204)
        let client = JellyfinSubtitleClient(session: session)

        try await client.downloadRemoteSubtitle(
            serverURL: server, token: "tok", itemId: "item-1", subtitleId: "sub1"
        )

        let request = try XCTUnwrap(session.capturedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/Items/item-1/RemoteSearch/Subtitles/sub1")
    }

    func testDownloadFailureThrows() async {
        let session = MockNetworkSession(data: Data(), statusCode: 404)
        let client = JellyfinSubtitleClient(session: session)

        do {
            try await client.downloadRemoteSubtitle(serverURL: server, token: "tok", itemId: "item-1", subtitleId: "nope")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SubtitleSearchError, .serverError(404))
        }
    }

    func testRemoteSubtitleDisplayName() {
        let info = RemoteSubtitleInfo(id: "a", providerName: "OpenSubtitles", name: "Movie.spa.srt", communityRating: 4.5)
        XCTAssertTrue(info.displayName.contains("Movie.spa.srt"))
        XCTAssertTrue(info.displayName.contains("OpenSubtitles"))
    }
}

// MARK: - Helpers

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected throw", file: file, line: line)
    } catch {
        verify(error)
    }
}

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
