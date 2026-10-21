import XCTest
@testable import ThisJellyFixCore

/// The episode's playback state comes from the server and from nowhere else:
/// an explicit `Played` flag means watched, a playback position means "in
/// progress", and nothing else means "unwatched".
final class EpisodeWatchStateTests: XCTestCase {

    private func episode(
        ticks: Int64? = nil,
        durationTicks: Int64? = 36_000_000_000, // 1 h (10 000 000 ticks per second)
        percentage: Double? = nil,
        played: Bool? = nil
    ) -> JellyfinEpisode {
        JellyfinEpisode(
            id: "e1",
            name: "Episodio",
            overview: nil,
            indexNumber: 1,
            parentIndexNumber: 1,
            runTimeTicks: durationTicks,
            seriesId: "s1",
            seriesName: "Serie",
            seasonName: "Temporada 1",
            imageTags: nil,
            userData: UserData(
                playbackPositionTicks: ticks,
                playedPercentage: percentage,
                isFavorite: nil,
                played: played
            )
        )
    }

    func testNeverStartedIsUnwatched() {
        XCTAssertEqual(episode().watchState, .unwatched)
    }

    func testZeroPositionIsUnwatched() {
        XCTAssertEqual(episode(ticks: 0).watchState, .unwatched)
    }

    func testPlayedFlagWinsOverResidualPosition() {
        let state = episode(ticks: 600_000_000, percentage: 16, played: true).watchState
        XCTAssertEqual(state, .watched)
    }

    func testPlayedFalseWithFullPercentageIsInProgress() {
        let state = episode(ticks: 3_600_000_000, percentage: 100, played: false).watchState
        XCTAssertEqual(state, .inProgress(fraction: 1.0))
    }

    func testFractionIsDerivedFromPositionAndDuration() {
        // 30 min of a 60 min episode.
        let state = episode(ticks: 18_000_000_000).watchState
        XCTAssertEqual(state, .inProgress(fraction: 0.5))
    }

    func testServerPercentageWinsOverDerivedFraction() {
        let state = episode(ticks: 600_000_000, percentage: 25).watchState
        XCTAssertEqual(state, .inProgress(fraction: 0.25))
    }

    func testUnknownDurationYieldsInProgressWithoutFraction() {
        let state = episode(ticks: 600_000_000, durationTicks: nil).watchState
        XCTAssertEqual(state, .inProgress(fraction: nil))
    }

    func testFractionIsClampedToOne() {
        let state = episode(ticks: 7_200_000_000, percentage: 140).watchState
        XCTAssertEqual(state, .inProgress(fraction: 1.0))
    }

    func testDurationSecondsConvertsTicks() {
        XCTAssertEqual(episode().durationSeconds, 3600)
        XCTAssertNil(episode(durationTicks: nil).durationSeconds)
    }

    func testPlayedFlagIsReadFromUserData() {
        XCTAssertTrue(episode(played: true).isPlayed)
        XCTAssertFalse(episode(played: false).isPlayed)
        XCTAssertFalse(episode().isPlayed)
    }
}
