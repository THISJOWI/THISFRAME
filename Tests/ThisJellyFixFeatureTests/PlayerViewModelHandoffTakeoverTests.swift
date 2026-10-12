import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Handoff takeover: when another device starts playing the same item, this
/// device must stop and surface who took over (NSUserActivity is one-way —
/// /Sessions polling is the only signal available).
@MainActor
final class PlayerViewModelHandoffTakeoverTests: XCTestCase {

    private func makeConfiguredVM(sessionClient: any JellyfinSessionProviding) -> PlayerViewModel {
        let vm = PlayerViewModel()
        vm.sessionClient = sessionClient
        vm.configureReporting(
            userId: "u1",
            serverURL: URL(string: "http://localhost:1")!,
            token: "tok",
            itemId: "item-1"
        )
        return vm
    }

    func testTakeoverFiresWhenOtherDevicePlaysSameItem() async {
        let vm = makeConfiguredVM(sessionClient: StubSessionClient(sessions: [
            ActiveSessionInfo(
                deviceId: "other-tv", userId: "u1", deviceName: "Salón",
                nowPlayingItemId: "item-1", isPaused: false
            ),
        ]))

        await vm.checkHandoffTakeover()

        XCTAssertEqual(vm.handoffTakeoverDeviceName, "Salón")
        XCTAssertTrue(vm.engineStopped, "the old device must stop playback")
    }

    func testNoTakeoverWhileThisSessionStartedFromHandoff() async {
        // The RECEIVING device sees the sender's still-active session for a
        // few seconds — it must never yield back (that would stop both).
        let vm = makeConfiguredVM(sessionClient: StubSessionClient(sessions: [
            ActiveSessionInfo(
                deviceId: "sender-iphone", userId: "u1", deviceName: "iPhone",
                nowPlayingItemId: "item-1", isPaused: false
            ),
        ]))
        vm.receivedViaHandoff = true

        await vm.checkHandoffTakeover()

        XCTAssertNil(vm.handoffTakeoverDeviceName)
        XCTAssertFalse(vm.engineStopped)
    }

    func testNoTakeoverWhenNoOtherDevicePlaysTheItem() async {
        let vm = makeConfiguredVM(sessionClient: StubSessionClient(sessions: [
            ActiveSessionInfo(
                deviceId: DeviceIdentifier().current(), userId: "u1",
                deviceName: "Este dispositivo",
                nowPlayingItemId: "item-1", isPaused: false
            ),
        ]))

        await vm.checkHandoffTakeover()

        XCTAssertNil(vm.handoffTakeoverDeviceName)
        XCTAssertFalse(vm.engineStopped)
    }

    func testNoTakeoverWhenAnotherUserPlaysTheItem() async {
        // Admin accounts see every user's sessions on the server — another
        // USER watching the same item is not a handoff takeover.
        let vm = makeConfiguredVM(sessionClient: StubSessionClient(sessions: [
            ActiveSessionInfo(
                deviceId: "other-tv", userId: "someone-else", deviceName: "Salón",
                nowPlayingItemId: "item-1", isPaused: false
            ),
        ]))

        await vm.checkHandoffTakeover()

        XCTAssertNil(vm.handoffTakeoverDeviceName)
        XCTAssertFalse(vm.engineStopped)
    }

    func testConcurrentChecksFetchSessionsOnlyOnce() async {
        let stub = StubSessionClient(sessions: [
            ActiveSessionInfo(
                deviceId: "other-tv", userId: "u1", deviceName: "Salón",
                nowPlayingItemId: "item-1", isPaused: false
            ),
        ])
        stub.delayNanoseconds = 200_000_000
        let vm = makeConfiguredVM(sessionClient: stub)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await vm.checkHandoffTakeover() }
            group.addTask { await vm.checkHandoffTakeover() }
            await group.waitForAll()
        }

        XCTAssertEqual(stub.fetchCount, 1, "in-flight guard must skip the second check")
        XCTAssertEqual(vm.handoffTakeoverDeviceName, "Salón")
    }
}

// MARK: - Stub

private final class StubSessionClient: JellyfinSessionProviding, @unchecked Sendable {
    let sessions: [ActiveSessionInfo]
    var delayNanoseconds: UInt64 = 0
    private(set) var fetchCount = 0

    init(sessions: [ActiveSessionInfo]) {
        self.sessions = sessions
    }

    func fetchActiveSessions(serverURL: URL, token: String) async throws -> [ActiveSessionInfo] {
        fetchCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return sessions
    }
}
