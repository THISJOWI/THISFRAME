import XCTest
@testable import ThisJellyFixCore

/// T-cast1 — máquina de estados de sesión Cast. Refleja las garantías que la
/// UI necesita: un evento tardío de un intento viejo nunca pisa una sesión
/// viva, y los comandos de transporte se bloquean mientras se negocia.
final class CastSessionStateTests: XCTestCase {
    func testInitialStateIsIdle() {
        let state = CastSessionState()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.lastDeviceName)
        XCTAssertFalse(state.blocksTransportCommands)
    }

    func testDiscoveryMovesToDiscovering() {
        var state = CastSessionState()
        state.discoveryRequested()
        XCTAssertEqual(state.phase, .discovering)
    }

    func testConnectSequenceHappyPath() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        XCTAssertEqual(state.phase, .connecting(deviceName: "Salón"))
        XCTAssertTrue(state.blocksTransportCommands)

        state.sessionStarted(name: "Salón")
        XCTAssertEqual(state.phase, .connected(deviceName: "Salón"))
        XCTAssertEqual(state.lastDeviceName, "Salón")
        XCTAssertFalse(state.blocksTransportCommands)
    }

    func testSessionStartedWithDifferentNameIgnored() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        state.sessionStarted(name: "Cocina")
        XCTAssertEqual(state.phase, .connecting(deviceName: "Salón"))
    }

    func testLateStartAfterConnectedDoesNotDowngrade() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        state.sessionStarted(name: "Salón")
        state.sessionStarted(name: "Cocina")
        XCTAssertEqual(state.phase, .connected(deviceName: "Salón"))
    }

    func testFailureWhileConnecting() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        state.failed(reason: "timeout")
        XCTAssertEqual(state.phase, .failed(reason: "timeout"))
    }

    func testLateFailureDoesNotKillLiveSession() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        state.sessionStarted(name: "Salón")
        state.failed(reason: "stale")
        XCTAssertEqual(state.phase, .connected(deviceName: "Salón"))
    }

    func testSessionEndedReturnsToIdle() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        state.sessionStarted(name: "Salón")
        state.sessionEnded()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.lastDeviceName, "Salón", "recuerda el último dispositivo para reconectar")
    }

    func testAcknowledgeFailureClearsToIdle() {
        var state = CastSessionState()
        state.failed(reason: "boom")
        state.acknowledgeFailure()
        XCTAssertEqual(state.phase, .idle)
    }

    func testDiscoveryWhileConnectedKeepsSession() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        state.sessionStarted(name: "Salón")
        state.discoveryRequested()
        XCTAssertEqual(state.phase, .connected(deviceName: "Salón"))
    }

    func testResetClearsEverything() {
        var state = CastSessionState()
        state.deviceSelected(name: "Salón")
        state.sessionStarted(name: "Salón")
        state.reset()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.lastDeviceName)
    }
}
