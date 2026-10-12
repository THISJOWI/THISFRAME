import XCTest
@testable import ThisJellyFixCore

/// T-cast3 — MIME que el receptor necesita para abrir el stream.
final class CastContentTypeTests: XCTestCase {
    func testHLSPlaylistDetected() {
        let url = URL(string: "http://192.168.1.5:8096/Videos/abc/master.m3u8?ApiKey=x")!
        XCTAssertEqual(CastContentType.detect(from: url), CastContentType.hls)
    }

    func testMP4Detected() {
        let url = URL(string: "http://192.168.1.5:8096/Videos/abc/stream.mp4?ApiKey=x")!
        XCTAssertEqual(CastContentType.detect(from: url), CastContentType.mp4)
    }

    func testM4VDetectedCaseInsensitive() {
        let url = URL(string: "http://192.168.1.5:8096/a.M4V")!
        XCTAssertEqual(CastContentType.detect(from: url), CastContentType.mp4)
    }

    func testExtensionlessFallsBackToMP4() {
        // /Videos/{id}/stream sin extensión — el resolver de fallback la usa.
        let url = URL(string: "http://192.168.1.5:8096/Videos/abc/stream?static=true&ApiKey=x")!
        XCTAssertEqual(CastContentType.detect(from: url), CastContentType.unknownStream)
    }
}
