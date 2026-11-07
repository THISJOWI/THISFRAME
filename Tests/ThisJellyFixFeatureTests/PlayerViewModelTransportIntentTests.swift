import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixPlayback

/// Regression for the Outline report "el botón de play sigue apareciendo
/// cuando la reproducción se queda pensando" (and the follow-up: both glyphs
/// kept appearing, i.e. it flickered).
///
/// The glyph must follow playback INTENT, never engine state: `isPlaying`
/// reads false every time AVPlayer waits on the network, so deriving the icon
/// from it flashed PLAY (and alternated play/pause) during buffering.
@MainActor
final class PlayerViewModelTransportIntentTests: XCTestCase {

    func testStartsPausedSoTheTransportOffersPlay() {
        let vm = PlayerViewModel()
        XCTAssertTrue(vm.userPaused)
    }

    func testToggleFlipsIntentAndSurvivesBufferingReads() async {
        let vm = PlayerViewModel()

        await vm.togglePlayPause()
        XCTAssertFalse(vm.userPaused, "requesting playback must show PAUSE")

        // The 0.5 s tick mirrors engine truth; a stall makes it read false.
        // Intent must not change, or the icon would flicker back to PLAY.
        vm.isPlaying = false
        XCTAssertFalse(vm.userPaused)

        await vm.togglePlayPause()
        XCTAssertTrue(vm.userPaused, "a deliberate pause must show PLAY")
    }

    func testEngineEndRestoresPlayGlyph() {
        let vm = PlayerViewModel()
        vm.userPaused = false

        vm.handleEngineState(.ended(itemID: "x"))

        XCTAssertTrue(vm.userPaused, "a finished item must offer PLAY again")
    }

    func testEngineFailureRestoresPlayGlyph() {
        let vm = PlayerViewModel()
        vm.userPaused = false

        vm.handleEngineState(.failed("boom"))

        XCTAssertTrue(vm.userPaused)
    }
}
