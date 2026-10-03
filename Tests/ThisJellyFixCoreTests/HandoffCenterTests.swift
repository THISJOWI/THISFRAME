import XCTest
@testable import ThisJellyFixCore

/// T4 — the browsing activity must YIELD while playback owns Handoff:
/// two eligible activities competing is how the Mac Dock advertised
/// "browsing" (whose macOS handler does nothing) instead of "playing".
@MainActor
final class HandoffCenterTests: XCTestCase {
    func testPlaybackOwnsHandoffOnlyWhileActive() {
        let center = HandoffCenter()
        XCTAssertFalse(center.isPlaybackActive)
        XCTAssertTrue(center.shouldPublishBrowsing)

        center.setPlaybackActive(true)
        XCTAssertTrue(center.isPlaybackActive)
        XCTAssertFalse(center.shouldPublishBrowsing)

        center.setPlaybackActive(false)
        XCTAssertFalse(center.isPlaybackActive)
        XCTAssertTrue(center.shouldPublishBrowsing)
    }

    func testBrowsingYieldsAgainAfterPlaybackStops() {
        let center = HandoffCenter()
        center.setPlaybackActive(true)
        center.setPlaybackActive(true) // idempotent
        XCTAssertFalse(center.shouldPublishBrowsing)
        center.setPlaybackActive(false)
        XCTAssertTrue(center.shouldPublishBrowsing)
    }
}
