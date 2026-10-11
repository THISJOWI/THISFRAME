import XCTest
@testable import ThisJellyFixCore
@testable import ThisJellyFixFeature

final class CardBadgeTests: XCTestCase {
    /// Fixed clock: 2026-10-11 12:00 UTC — all fixtures are relative to it.
    private let now = Date(timeIntervalSince1970: 1_791_720_000)
    /// UTC calendar: same-day checks must not depend on the host timezone.
    private var utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func makeItem(
        id: String = "i1",
        type: String = "Movie",
        played: Bool? = false,
        dateCreated: String? = nil,
        dateLastMediaAdded: String? = nil
    ) -> JellyfinMediaItem {
        JellyfinMediaItem(
            id: id,
            name: "Title",
            type: type,
            userData: UserData(
                playbackPositionTicks: nil,
                playedPercentage: nil,
                isFavorite: nil,
                played: played
            ),
            dateCreated: dateCreated,
            dateLastMediaAdded: dateLastMediaAdded
        )
    }

    func testResumeItemGetsNextEpisodeBadge() {
        let item = makeItem(id: "r1")
        XCTAssertEqual(
            CardBadge.badge(for: item, resumeItems: ["r1"], now: now, calendar: utc),
            .nextEpisode(day: nil)
        )
    }

    func testSeriesWithoutDatesGetsNoBadge() {
        // Unwatched alone no longer means "Nueva temporada" — the old rule
        // produced fake badges on every series in the library.
        let item = makeItem(id: "s1", type: "Series", played: false)
        XCTAssertNil(CardBadge.badge(for: item, resumeItems: [], now: now, calendar: utc))
    }

    func testSeriesWithOldDateGetsNoBadge() {
        let item = makeItem(
            id: "s2", type: "Series",
            dateCreated: "2020-01-01T00:00:00.0000000Z"
        )
        XCTAssertNil(CardBadge.badge(for: item, resumeItems: [], now: now, calendar: utc))
    }

    func testVerifiedNewSeasonGetsBadge() {
        let item = makeItem(
            id: "s3", type: "Series",
            dateCreated: "2020-01-01T00:00:00.0000000Z"
        )
        XCTAssertEqual(
            CardBadge.badge(
                for: item, resumeItems: [],
                verifiedNewSeasonIDs: ["s3"], now: now, calendar: utc
            ),
            .newSeason
        )
    }

    func testEpisodeAddedTodayGetsNewEpisodeBadge() {
        // 6 hours before the fixed clock — same calendar day.
        let item = makeItem(
            id: "e1", type: "Episode",
            dateCreated: "2026-10-11T06:00:00.0000000Z"
        )
        XCTAssertEqual(
            CardBadge.badge(for: item, resumeItems: [], now: now, calendar: utc),
            .newEpisodeToday
        )
    }

    func testEpisodeAddedYesterdayGetsRecentlyAddedNotNewToday() {
        // Yesterday's incorporation is recent but NOT "Nuevo hoy" — the
        // same-day rule is what distinguishes a premiere-day episode.
        let item = makeItem(
            id: "e2", type: "Episode",
            dateCreated: "2026-10-10T23:00:00.0000000Z"
        )
        XCTAssertEqual(
            CardBadge.badge(for: item, resumeItems: [], now: now, calendar: utc),
            .recentlyAdded
        )
    }

    func testMovieAddedWithinWindowGetsRecentlyAddedBadge() {
        let item = makeItem(
            id: "m1", type: "Movie",
            dateCreated: "2026-09-20T00:00:00.0000000Z" // 21 days before now
        )
        XCTAssertEqual(
            CardBadge.badge(for: item, resumeItems: [], now: now, calendar: utc),
            .recentlyAdded
        )
    }

    func testMovieAddedBeyondWindowGetsNoBadge() {
        let item = makeItem(
            id: "m2", type: "Movie",
            dateCreated: "2026-08-01T00:00:00.0000000Z" // 71 days before now
        )
        XCTAssertNil(CardBadge.badge(for: item, resumeItems: [], now: now, calendar: utc))
    }

    func testFutureDateGetsNoBadge() {
        // Clock skew must not mint a novelty badge.
        let item = makeItem(
            id: "m3", type: "Movie",
            dateCreated: "2026-12-25T00:00:00.0000000Z"
        )
        XCTAssertNil(CardBadge.badge(for: item, resumeItems: [], now: now, calendar: utc))
    }

    func testResumeTakesPrecedenceOverNovelty() {
        let item = makeItem(
            id: "s4", type: "Series",
            dateCreated: "2026-10-01T00:00:00.0000000Z"
        )
        XCTAssertEqual(
            CardBadge.badge(
                for: item, resumeItems: ["s4"],
                verifiedNewSeasonIDs: ["s4"], now: now, calendar: utc
            ),
            .nextEpisode(day: nil)
        )
    }
}
