import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixCore
import ThisJellyFixNetworking
import ThisJellyFixPlayback

/// End-of-episode behaviour: the REAL end of media must report a stop at the
/// final position (Jellyfin marks the item played from it), exactly once, and
/// must never be confused with a user exiting early. The server owns the
/// watched flag, so no local optimistic state is involved.
@MainActor
final class PlayerViewModelCompletionTests: XCTestCase {

    private func makeVM(
        duration: Double = 2400,
        currentTime: Double = 0
    ) -> (PlayerViewModel, StubPlaybackReporter) {
        let vm = PlayerViewModel()
        let reporter = StubPlaybackReporter()
        vm.reporter = reporter
        vm.configureReporting(
            userId: "u1",
            serverURL: URL(string: "http://localhost:1")!,
            token: "tok",
            itemId: "ep-1",
            playSessionId: "ps-1"
        )
        vm.duration = duration
        vm.currentTime = currentTime
        return (vm, reporter)
    }

    // MARK: - Real end

    func testNaturalEndReportsStopAtTheFullDuration() async {
        // AVPlayer's clock can be a few frames short when the end notification
        // arrives; the event itself is authoritative for the whole item.
        let (vm, reporter) = makeVM(duration: 2400, currentTime: 2399.4)

        vm.handleEngineState(.ended(itemID: "ep-1"))
        await vm.flushReports()

        XCTAssertEqual(reporter.stops.count, 1)
        XCTAssertEqual(reporter.stops[0].itemId, "ep-1")
        XCTAssertEqual(reporter.stops[0].positionTicks, Int64(2400 * 10_000_000))
        XCTAssertEqual(reporter.stops[0].playSessionId, "ps-1")
        XCTAssertEqual(vm.currentTime, 2400)
        XCTAssertFalse(vm.isPlaying)
    }

    func testEndIsReportedOnlyOnce() async {
        let (vm, reporter) = makeVM(duration: 2400, currentTime: 2399)

        vm.handleEngineState(.ended(itemID: "ep-1"))
        vm.handleEngineState(.ended(itemID: "ep-1"))
        await vm.flushReports()

        XCTAssertEqual(reporter.stops.count, 1, "duplicate end events must collapse")

        // The exit path runs teardown after the end: it must not send a second,
        // stale stop for the same item.
        vm.stopSync(reportStop: true)
        await vm.flushReports()

        XCTAssertEqual(reporter.stops.count, 1)
    }

    func testCompletionCallbackFiresExactlyOnce() async {
        let (vm, _) = makeVM(duration: 2400, currentTime: 2399)
        var completions = 0
        vm.onPlaybackCompleted = { completions += 1 }

        vm.handleEngineState(.ended(itemID: "ep-1"))
        vm.handleEngineState(.ended(itemID: "ep-1"))
        await vm.flushReports()

        XCTAssertEqual(completions, 1)
    }

    func testEndNotificationFromASwappedItemIsIgnored() async {
        let (vm, reporter) = makeVM(duration: 2400, currentTime: 30)
        var completions = 0
        vm.onPlaybackCompleted = { completions += 1 }

        // An episode swap already configured the new item; the previous item's
        // end notification must not complete it.
        vm.handleEngineState(.ended(itemID: "ep-previous"))
        await vm.flushReports()

        XCTAssertTrue(reporter.stops.isEmpty)
        XCTAssertEqual(completions, 0)
    }

    // MARK: - Early exit

    func testExitBeforeTheEndKeepsPartialProgress() async {
        let (vm, reporter) = makeVM(duration: 2400, currentTime: 600)
        var completions = 0
        vm.onPlaybackCompleted = { completions += 1 }

        vm.stopSync(reportStop: true)
        await vm.flushReports()

        XCTAssertEqual(reporter.stops.count, 1)
        XCTAssertEqual(reporter.stops[0].positionTicks, Int64(600 * 10_000_000))
        XCTAssertEqual(completions, 0, "a partial exit is not a completed episode")
    }

    // MARK: - Effective end fallback

    func testFallbackCompletesWhenPlayheadSitsOnTheDuration() async {
        let (vm, reporter) = makeVM(duration: 100, currentTime: 100)
        vm.isPlaying = false
        vm.isSeeking = false

        vm.evaluatePlaybackEnd()
        await vm.flushReports()

        XCTAssertEqual(reporter.stops.count, 1)
        XCTAssertEqual(reporter.stops[0].positionTicks, Int64(100 * 10_000_000))
    }

    func testFallbackDoesNotFireBeforeTheEnd() async {
        let (vm, reporter) = makeVM(duration: 100, currentTime: 99.9)
        vm.isPlaying = false
        vm.isSeeking = false

        vm.evaluatePlaybackEnd()
        await vm.flushReports()

        XCTAssertTrue(reporter.stops.isEmpty)
    }

    func testFallbackDoesNotFireWhileSeeking() async {
        let (vm, reporter) = makeVM(duration: 100, currentTime: 100)
        vm.isPlaying = false
        vm.isSeeking = true

        vm.evaluatePlaybackEnd()
        await vm.flushReports()

        XCTAssertTrue(reporter.stops.isEmpty, "a scrub to the end is not a played item")
    }

    // MARK: - Report ordering

    func testStopIsSerialisedAfterAnInFlightProgressReport() async {
        let (vm, reporter) = makeVM(duration: 100, currentTime: 50)
        reporter.reportDelayNanoseconds = 50_000_000

        // A progress POST is already queued when the item ends.
        vm.reportProgress()
        vm.currentTime = 100
        vm.handleEngineState(.ended(itemID: "ep-1"))
        await vm.flushReports()

        XCTAssertEqual(reporter.events, [.progress, .stop])
    }
}

// MARK: - Stub

private final class StubPlaybackReporter: JellyfinPlaybackReporting, @unchecked Sendable {
    enum Event: Equatable {
        case playing
        case progress
        case stop
    }

    struct Stop: Equatable {
        let itemId: String
        let positionTicks: Int64
        let playSessionId: String?
    }

    var playSessionId: String?
    var reportDelayNanoseconds: UInt64 = 0

    private(set) var events: [Event] = []
    private(set) var stops: [Stop] = []

    func reportPlaying(
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        mediaSourceId: String
    ) async {
        events.append(.playing)
    }

    func reportProgress(
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        mediaSourceId: String,
        positionTicks: Int64,
        isPaused: Bool
    ) async {
        if reportDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: reportDelayNanoseconds)
        }
        events.append(.progress)
    }

    func reportStopped(
        userId: String,
        serverURL: URL,
        token: String,
        itemId: String,
        mediaSourceId: String,
        positionTicks: Int64
    ) async {
        events.append(.stop)
        stops.append(
            Stop(itemId: itemId, positionTicks: positionTicks, playSessionId: playSessionId)
        )
    }
}
