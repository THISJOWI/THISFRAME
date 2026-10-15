import XCTest
@testable import ThisJellyFixNetworking
import ThisJellyFixCore

final class JellyfinPlaybackClientTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    private let validJSON = """
    {"MediaSources":[{"Id":"src1","Name":"video","Path":"/v.mp4","Protocol":"Http","Container":"mp4"}]}
    """

    func testMaxStreamingBitrateIsSentInBody() async throws {
        let session = MockNetworkSession(data: Data(validJSON.utf8), statusCode: 200)
        let client = JellyfinPlaybackClient(session: session)

        _ = try await client.fetchPlaybackInfo(
            userId: "u1", serverURL: server, token: "tok", itemId: "i9",
            deviceProfile: nil, maxStreamingBitrate: 4_000_000
        )

        let request = try XCTUnwrap(session.capturedRequest)
        XCTAssertEqual(request.url?.path, "/Items/i9/PlaybackInfo")
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        XCTAssertEqual(body["MaxStreamingBitrate"] as? Int, 4_000_000)
    }

    func testNoCapSendsNoMaxStreamingBitrate() async throws {
        let session = MockNetworkSession(data: Data(validJSON.utf8), statusCode: 200)
        let client = JellyfinPlaybackClient(session: session)

        _ = try await client.fetchPlaybackInfo(
            userId: "u1", serverURL: server, token: "tok", itemId: "i9",
            deviceProfile: nil, maxStreamingBitrate: nil
        )

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        XCTAssertNil(body["MaxStreamingBitrate"])
    }

    func testSubtitleStreamIndexDefaultsToMinusOne() async throws {
        let session = MockNetworkSession(data: Data(validJSON.utf8), statusCode: 200)
        let client = JellyfinPlaybackClient(session: session)

        _ = try await client.fetchPlaybackInfo(
            userId: "u1", serverURL: server, token: "tok", itemId: "i9",
            deviceProfile: nil
        )

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        // -1 = no subtitle selected/burned server-side; the client overlay
        // is the single subtitle renderer (kills the background-less copy).
        XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, -1)
    }

    func testAlwaysBurnInSubtitleDefaultsToFalse() async throws {
        let session = MockNetworkSession(data: Data(validJSON.utf8), statusCode: 200)
        let client = JellyfinPlaybackClient(session: session)

        _ = try await client.fetchPlaybackInfo(
            userId: "u1", serverURL: server, token: "tok", itemId: "i9",
            deviceProfile: nil
        )

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        XCTAssertEqual(body["AlwaysBurnInSubtitleWhenTranscoding"] as? Bool, false)
    }

    func testNilSubtitleOptionsOptOut() async throws {
        let session = MockNetworkSession(data: Data(validJSON.utf8), statusCode: 200)
        let client = JellyfinPlaybackClient(session: session)

        _ = try await client.fetchPlaybackInfo(
            userId: "u1", serverURL: server, token: "tok", itemId: "i9",
            deviceProfile: nil, subtitleStreamIndex: nil,
            alwaysBurnInSubtitleWhenTranscoding: nil
        )

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        XCTAssertNil(body["SubtitleStreamIndex"])
        XCTAssertNil(body["AlwaysBurnInSubtitleWhenTranscoding"])
    }

    func testAudioStreamIndexIsSentWhenProvided() async throws {
        let session = MockNetworkSession(data: Data(validJSON.utf8), statusCode: 200)
        let client = JellyfinPlaybackClient(session: session)

        _ = try await client.fetchPlaybackInfo(
            userId: "u1", serverURL: server, token: "tok", itemId: "i9",
            deviceProfile: nil, audioStreamIndex: 2
        )

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        XCTAssertEqual(body["AudioStreamIndex"] as? Int, 2)
    }

    func testAudioStreamIndexOmittedByDefault() async throws {
        let session = MockNetworkSession(data: Data(validJSON.utf8), statusCode: 200)
        let client = JellyfinPlaybackClient(session: session)

        _ = try await client.fetchPlaybackInfo(
            userId: "u1", serverURL: server, token: "tok", itemId: "i9",
            deviceProfile: nil
        )

        let request = try XCTUnwrap(session.capturedRequest)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        // Sin índice el servidor sirve su default (comportamiento anterior).
        XCTAssertNil(body["AudioStreamIndex"])
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
