import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixCore

/// Transport/volume helpers added for the controls redesign: tick math is
/// pure; the previous/next guards must not fire callbacks that aren't wired.
@MainActor
final class PlayerViewModelControlTests: XCTestCase {

    // MARK: - Segment tick fractions (seek bar chapter ticks)

    func testTickFractionsNormalizesToDuration() {
        let markers = [
            SegmentMarker(type: .intro, start: 90, end: 150),
            SegmentMarker(type: .credits, start: 1200, end: nil),
        ]
        let ticks = PlayerViewModel.tickFractions(markers: markers, duration: 2400)
        XCTAssertEqual(ticks, [0.0375, 0.5])
    }

    func testTickFractionsDropsZeroDuration() {
        let markers = [SegmentMarker(type: .intro, start: 90, end: 150)]
        XCTAssertEqual(PlayerViewModel.tickFractions(markers: markers, duration: 0), [])
        XCTAssertEqual(PlayerViewModel.tickFractions(markers: markers, duration: .nan), [])
    }

    func testTickFractionsSkipsStartAtZeroAndPastTheEnd() {
        let markers = [
            SegmentMarker(type: .intro, start: 0, end: 30),
            SegmentMarker(type: .credits, start: 2500, end: nil),
        ]
        XCTAssertEqual(PlayerViewModel.tickFractions(markers: markers, duration: 2400), [])
    }

    // MARK: - Volume

    func testSetVolumeClampsAndAppliesToPlayer() {
        let vm = PlayerViewModel()
        vm.setVolume(1.7)
        XCTAssertEqual(vm.volume, 1.0)
        XCTAssertEqual(vm.engine.player.volume, 1.0)

        vm.setVolume(-0.3)
        XCTAssertEqual(vm.volume, 0.0)
        XCTAssertEqual(vm.engine.player.volume, 0.0)

        vm.setVolume(0.42)
        XCTAssertEqual(vm.volume, 0.42, accuracy: 0.0001)
        XCTAssertEqual(vm.engine.player.volume, 0.42, accuracy: 0.0001)
    }

    // MARK: - Previous/next episode guards

    func testPlayPreviousEpisodeDoesNothingWhenUnwired() {
        let vm = PlayerViewModel()
        var fired = false
        vm.onPlayPreviousEpisode = { fired = true }

        vm.playPreviousEpisode() // hasPreviousEpisode == false
        XCTAssertFalse(fired)

        vm.hasPreviousEpisode = true
        vm.playPreviousEpisode()
        XCTAssertTrue(fired)
    }

    func testPlayNextNowDoesNothingWhenUnwired() {
        let vm = PlayerViewModel()
        var fired = false
        vm.onPlayNextEpisode = { fired = true }

        vm.playNextNow() // hasNextEpisode == false
        XCTAssertFalse(fired)

        vm.hasNextEpisode = true
        vm.playNextNow()
        XCTAssertTrue(fired)
    }

    /// Unlike the credits auto-offer, `playNextNow` must fire regardless of
    /// segment state — the transport button is a deliberate tap.
    func testPlayNextNowIgnoresCreditsGuard() {
        let vm = PlayerViewModel()
        var fired = false
        vm.hasNextEpisode = true
        vm.onPlayNextEpisode = { fired = true }
        vm.activeSegment = SegmentMarker(type: .intro, start: 0, end: 30)

        vm.playNextNow()
        XCTAssertTrue(fired)
    }
}
