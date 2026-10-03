import XCTest
@testable import ThisJellyFixPlayback

/// T5 — AirPlay route lifecycle. Without an explicit state machine the
/// connection window was invisible: the VM's timer flipped `isPlaying`,
/// transport taps aborted the handoff and a `replaceCurrentItem` mid-connect
/// silently reverted to local playback.
final class AirPlayRouteStateTests: XCTestCase {
    func testStartsIdle() {
        let state = AirPlayRouteState()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.isConnecting)
        XCTAssertFalse(state.blocksTransportCommands)
    }

    func testRouteSelectedEntersConnecting() {
        var state = AirPlayRouteState()
        state.routeSelected(name: "Apple TV")
        XCTAssertEqual(state.phase, .connecting(routeName: "Apple TV"))
        XCTAssertTrue(state.isConnecting)
        XCTAssertTrue(state.blocksTransportCommands)
    }

    func testExternalPlaybackActiveEntersActive() {
        var state = AirPlayRouteState()
        state.routeSelected(name: "Apple TV")
        state.externalPlaybackChanged(true)
        XCTAssertEqual(state.phase, .active)
        XCTAssertFalse(state.blocksTransportCommands)
    }

    func testTimeoutFailsOnlyWhileConnecting() {
        var state = AirPlayRouteState()
        state.routeSelected(name: "Apple TV")
        state.timedOut()
        XCTAssertEqual(state.phase, .failed(reason: "Apple TV no respondió en 10 s"))

        var idle = AirPlayRouteState()
        idle.timedOut()
        XCTAssertEqual(idle.phase, .idle)

        var active = AirPlayRouteState()
        active.routeSelected(name: "Apple TV")
        active.externalPlaybackChanged(true)
        active.timedOut()
        XCTAssertEqual(active.phase, .active)
    }

    func testItemReplacedDuringConnectFailsExplicitly() {
        var state = AirPlayRouteState()
        state.routeSelected(name: "Apple TV")
        state.noteItemReplaced()
        XCTAssertEqual(state.phase, .failed(reason: "cambio de contenido durante la conexión"))
        XCTAssertFalse(state.blocksTransportCommands)
    }

    func testItemReplacedOutsideConnectKeepsPhase() {
        var state = AirPlayRouteState()
        state.noteItemReplaced()
        XCTAssertEqual(state.phase, .idle)

        state.routeSelected(name: "Apple TV")
        state.externalPlaybackChanged(true)
        state.noteItemReplaced()
        XCTAssertEqual(state.phase, .active)
    }

    func testRouteLostWhileActiveReturnsToIdle() {
        var state = AirPlayRouteState()
        state.routeSelected(name: "Apple TV")
        state.externalPlaybackChanged(true)
        state.noteRouteLost()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.selectedRouteName)
    }

    func testRetryingAfterFailureStartsFreshConnecting() {
        var state = AirPlayRouteState()
        state.routeSelected(name: "Apple TV")
        state.timedOut()
        state.routeSelected(name: "Salón")
        XCTAssertEqual(state.phase, .connecting(routeName: "Salón"))
    }

    func testExternalActiveWithoutSelectionStillActivates() {
        // System-initiated AirPlay (Control Center, another app): the machine
        // must reflect reality even without our own selection event.
        var state = AirPlayRouteState()
        state.externalPlaybackChanged(true)
        XCTAssertEqual(state.phase, .active)
    }
}
