import XCTest
@testable import ThisJellyFixNetworking
import ThisJellyFixCore

/// The app hands the subtitle it downloaded to the server, which then
/// serves it like any other external subtitle.
final class JellyfinSubtitleUploadTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    func testUploadPostsTheDocumentedBody() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(), statusCode: 204)
        ])
        let client = JellyfinSubtitleClient(session: session)

        try await client.uploadExternalSubtitle(
            serverURL: server,
            token: "tok",
            itemId: "item-1",
            data: "1\n00:00:01,000 --> 00:00:02,000\nHola\n",
            language: "spa",
            format: "srt"
        )

        let request = try XCTUnwrap(session.capturedRequests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/Videos/item-1/Subtitles")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        // The server's UploadSubtitleDto rejects unknown fields, so the
        // payload spells out exactly the five it declares.
        XCTAssertEqual(Set(json.keys), ["Language", "Format", "IsForced", "IsHearingImpaired", "Data"])
        XCTAssertEqual(json["Language"] as? String, "spa")
        XCTAssertEqual(json["Format"] as? String, "srt")
        XCTAssertEqual(json["IsForced"] as? Bool, false)
        XCTAssertEqual(json["IsHearingImpaired"] as? Bool, false)
        XCTAssertEqual(json["Data"] as? String, "1\n00:00:01,000 --> 00:00:02,000\nHola\n")
    }

    func testUploadForwardsTheForcedAndHearingImpairedFlags() async throws {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(), statusCode: 204)
        ])
        let client = JellyfinSubtitleClient(session: session)

        try await client.uploadExternalSubtitle(
            serverURL: server,
            token: "tok",
            itemId: "item-1",
            data: "x",
            language: "eng",
            format: "vtt",
            isForced: true,
            isHearingImpaired: true
        )

        let body = try XCTUnwrap(session.capturedRequests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["IsForced"] as? Bool, true)
        XCTAssertEqual(json["IsHearingImpaired"] as? Bool, true)
    }

    func testUploadFailureMapsTheStatus() async {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(), statusCode: 403)
        ])
        let client = JellyfinSubtitleClient(session: session)

        do {
            try await client.uploadExternalSubtitle(
                serverURL: server,
                token: "tok",
                itemId: "item-1",
                data: "x",
                language: "spa",
                format: "srt"
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SubtitleSearchError, .serverError(403))
        }
    }

    func testUploadUnauthorizedMapsToTheLibraryError() async {
        let session = ScriptedNetworkSession(responses: [
            .init(data: Data(), statusCode: 401)
        ])
        let client = JellyfinSubtitleClient(session: session)

        do {
            try await client.uploadExternalSubtitle(
                serverURL: server,
                token: "tok",
                itemId: "item-1",
                data: "x",
                language: "spa",
                format: "srt"
            )
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? LibraryError, .unauthorized)
        }
    }
}
