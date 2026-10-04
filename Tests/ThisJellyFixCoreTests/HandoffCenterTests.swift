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

    /// F1-redo: the pushed DetailView claims the slot via onAppear/onDisappear
    /// — covers tap pushes, handoff pushes and nested stacks ([Item1,Item2])
    /// without inspecting NavigationPath (which exposes no elements).
    func testBrowsingYieldsWhileAnyDetailIsTop() {
        let center = HandoffCenter()
        center.setDetailActive(true)            // push Item1
        XCTAssertFalse(center.shouldPublishBrowsing)

        center.setDetailActive(true)            // push Item2 over Item1
        center.setDetailActive(false)           // pop Item2
        XCTAssertFalse(center.shouldPublishBrowsing, "Item1 still under Item2")

        center.setDetailActive(false)           // pop Item1
        XCTAssertTrue(center.shouldPublishBrowsing)
    }

    func testDetailFlagClampsAtZero() {
        let center = HandoffCenter()
        center.setDetailActive(false)           // spurious disappear
        XCTAssertTrue(center.shouldPublishBrowsing)
        center.setDetailActive(true)
        center.setDetailActive(false)
        center.setDetailActive(false)           // extra disappear
        XCTAssertTrue(center.shouldPublishBrowsing)
    }

    func testPlaybackAndDetailBothYieldToPlaying() {
        let center = HandoffCenter()
        center.setDetailActive(true)
        center.setPlaybackActive(true)
        XCTAssertFalse(center.shouldPublishBrowsing)
        center.setPlaybackActive(false)
        XCTAssertFalse(center.shouldPublishBrowsing, "detail still top")
        center.setDetailActive(false)
        XCTAssertTrue(center.shouldPublishBrowsing)
    }
}
