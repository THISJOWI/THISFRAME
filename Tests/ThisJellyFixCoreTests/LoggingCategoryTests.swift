import XCTest
@testable import ThisJellyFixCore

/// T1 — TJFLog category routing so every line lands in the right Console
/// subsystem/category (airplay, handoff, playback, network).
final class LoggingCategoryTests: XCTestCase {
    func testAirPlayMessagesRouteToAirPlay() {
        XCTAssertEqual(TJFLogRouting.category(for: "airplay: route selected ATV"), .airplay)
        XCTAssertEqual(TJFLogRouting.category(for: "airplay: picker presenting BEGIN"), .airplay)
        XCTAssertEqual(TJFLogRouting.category(for: "audio session: category=.playback configured"), .airplay)
    }

    func testHandoffMessagesRouteToHandoff() {
        XCTAssertEqual(TJFLogRouting.category(for: "handoff: received 'playing'"), .handoff)
        XCTAssertEqual(TJFLogRouting.category(for: "handoff: resolve deferred"), .handoff)
    }

    func testPlaybackMessagesRouteToPlayback() {
        XCTAssertEqual(TJFLogRouting.category(for: "prepare: ext=mp4"), .playback)
        XCTAssertEqual(TJFLogRouting.category(for: "engine FAILED item=x"), .playback)
        XCTAssertEqual(TJFLogRouting.category(for: "reportProgress itemId=x ticks=1"), .playback)
        XCTAssertEqual(TJFLogRouting.category(for: "pip: view exit -> floating"), .playback)
        XCTAssertEqual(TJFLogRouting.category(for: "subtitles: applied desired=1"), .playback)
        XCTAssertEqual(TJFLogRouting.category(for: "timer tick=1 isPlaying=true"), .playback)
    }

    func testNetworkMessagesRouteToNetwork() {
        XCTAssertEqual(TJFLogRouting.category(for: "extSubs load idx=1"), .network)
        XCTAssertEqual(TJFLogRouting.category(for: "segments fetch error attempt=1"), .network)
        XCTAssertEqual(TJFLogRouting.category(for: "Keychain save failed"), .network)
    }

    func testUnknownMessagesRouteToGeneral() {
        XCTAssertEqual(TJFLogRouting.category(for: "library loaded"), .general)
        XCTAssertEqual(TJFLogRouting.category(for: ""), .general)
    }
}
