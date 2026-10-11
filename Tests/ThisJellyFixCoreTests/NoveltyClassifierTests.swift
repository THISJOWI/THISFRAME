import XCTest
@testable import ThisJellyFixCore

final class NoveltyClassifierTests: XCTestCase {
    /// Fixed clock: 2026-10-11 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_720_000)
    private lazy var classifier = NoveltyClassifier(now: now)

    private func series(
        dateCreated: String?,
        dateLastMediaAdded: String? = nil
    ) -> JellyfinMediaItem {
        JellyfinMediaItem(
            id: "s1", name: "Show", type: "Series",
            dateCreated: dateCreated,
            dateLastMediaAdded: dateLastMediaAdded
        )
    }

    // MARK: - Date parsing

    func testParsesSevenDigitFraction() {
        // Jellyfin emits up to 7 fractional digits; ISO8601DateFormatter
        // rejects those, which would silently kill every date-backed badge.
        XCTAssertNotNil(
            JellyfinDate.parse("2026-10-11T06:00:00.1234567Z")
        )
    }

    func testParsesPlainTimestamp() {
        XCTAssertNotNil(JellyfinDate.parse("2026-10-11T06:00:00Z"))
    }

    func testRejectsNilEmptyGarbage() {
        XCTAssertNil(JellyfinDate.parse(nil))
        XCTAssertNil(JellyfinDate.parse(""))
        XCTAssertNil(JellyfinDate.parse("not-a-date"))
    }

    // MARK: - New season verification

    func testEstablishedSeriesWithRecentSeasonIsVerified() {
        let seasons = [
            JellyfinSeason(id: "t1", name: "Temporada 1", dateCreated: "2023-01-01T00:00:00Z"),
            JellyfinSeason(id: "t2", name: "Temporada 2", dateCreated: "2026-10-05T00:00:00Z"),
        ]
        XCTAssertTrue(
            classifier.hasVerifiedNewSeason(
                seriesDateCreated: "2022-06-01T00:00:00Z", seasons: seasons
            )
        )
    }

    func testBulkImportIsNotVerifiedNewSeason() {
        // Import masivo: series + seasons all created today → "Recién
        // añadido", never "Nueva temporada".
        let seasons = [
            JellyfinSeason(id: "t1", name: "Temporada 1", dateCreated: "2026-10-10T00:00:00Z"),
            JellyfinSeason(id: "t2", name: "Temporada 2", dateCreated: "2026-10-10T00:00:00Z"),
        ]
        XCTAssertFalse(
            classifier.hasVerifiedNewSeason(
                seriesDateCreated: "2026-10-10T00:00:00Z", seasons: seasons
            )
        )
    }

    func testAllOldSeasonsAreNotVerified() {
        let seasons = [
            JellyfinSeason(id: "t1", name: "Temporada 1", dateCreated: "2024-01-01T00:00:00Z"),
        ]
        XCTAssertFalse(
            classifier.hasVerifiedNewSeason(
                seriesDateCreated: "2020-01-01T00:00:00Z", seasons: seasons
            )
        )
    }

    func testMissingSeasonDatesFailVerification() {
        // No Dates answered → withhold the badge, never guess.
        let seasons = [
            JellyfinSeason(id: "t1", name: "Temporada 1", dateCreated: nil),
        ]
        XCTAssertFalse(
            classifier.hasVerifiedNewSeason(
                seriesDateCreated: "2020-01-01T00:00:00Z", seasons: seasons
            )
        )
    }

    // MARK: - Season candidate pre-filter

    func testCandidateNeedsOldSeriesAndRecentAddition() {
        let candidate = series(
            dateCreated: "2020-01-01T00:00:00Z",
            dateLastMediaAdded: "2026-10-01T00:00:00Z"
        )
        XCTAssertTrue(classifier.isSeasonCandidate(candidate))
    }

    func testRecentSeriesIsNotCandidate() {
        // Bulk imports create the series itself recently — no seasons fetch.
        let item = series(
            dateCreated: "2026-10-05T00:00:00Z",
            dateLastMediaAdded: "2026-10-05T00:00:00Z"
        )
        XCTAssertFalse(classifier.isSeasonCandidate(item))
    }

    func testSeriesWithoutDatesIsNotCandidate() {
        XCTAssertFalse(classifier.isSeasonCandidate(series(dateCreated: nil)))
    }

    // MARK: - Novelty classification

    func testFutureDateIsNotNovelty() {
        let item = JellyfinMediaItem(
            id: "m1", name: "Movie", type: "Movie",
            dateCreated: "2026-12-01T00:00:00Z"
        )
        XCTAssertNil(classifier.novelty(for: item))
    }
}
