import XCTest
@testable import ThisJellyFixCore

/// Regression for the Outline report "Botón de play: sigue apareciendo
/// cuando la reproducción se queda pensando" (and the follow-up: both glyphs
/// kept appearing, i.e. it flickered).
///
/// The glyph must follow the user's INTENT. On a Chromecast the receiver
/// reports its state asynchronously, so a status that still says "playing"
/// right after a pause tap used to flip the glyph back.
final class TransportIntentLatchTests: XCTestCase {

    func testStartsPausedSoTheTransportOffersPlay() {
        var latch = TransportIntentLatch()
        XCTAssertTrue(latch.isPaused)
    }

    func testLocalIntentWinsWhileTheReceiverHasNotConfirmedIt() {
        var latch = TransportIntentLatch()
        latch.setLocalIntent(paused: true)

        // The receiver still says "playing" — the command is in flight.
        let resolved = latch.apply(receiverPlaying: true)

        XCTAssertTrue(resolved, "the pause intent must survive a lagging receiver")
    }

    func testReceiverConfirmsTheCommandAndTheLatchReleases() {
        var latch = TransportIntentLatch()
        latch.setLocalIntent(paused: true)

        // The receiver applied the pause.
        let resolved = latch.apply(receiverPlaying: false)

        XCTAssertTrue(resolved)
        XCTAssertFalse(
            latch.hasPendingCommand,
            "a confirmed command must release the pending flag"
        )
    }

    func testReceiverIsAuthoritativeWithoutAPendingCommand() {
        var latch = TransportIntentLatch()
        latch.setLocalIntent(paused: false)
        _ = latch.apply(receiverPlaying: true) // confirms "playing"

        // The user paused from the Chromecast itself.
        let resolved = latch.apply(receiverPlaying: false)

        XCTAssertTrue(resolved, "a remote pause must be reflected in the glyph")
    }

    func testUnknownReceiverStateKeepsTheIntent() {
        var latch = TransportIntentLatch()
        latch.setLocalIntent(paused: false)

        let resolved = latch.apply(receiverPlaying: nil)

        XCTAssertFalse(resolved, "an unknown state must not change the intent")
    }
}
