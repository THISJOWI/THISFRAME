import XCTest
@testable import ThisJellyFixCore
@testable import ThisJellyFixFeature

final class CardBadgeTests: XCTestCase {
    private func makeItem(
        id: String = "i1",
        type: String = "Movie",
        played: Bool? = false
    ) -> JellyfinMediaItem {
        JellyfinMediaItem(
            id: id,
            name: "Title",
            type: type,
            overview: nil,
            seriesName: nil,
            indexNumber: nil,
            parentIndexNumber: nil,
            year: nil,
            imageTags: nil,
            backdropImageTags: nil,
            officialRating: nil,
            communityRating: nil,
            genres: nil,
            userData: UserData(
                playbackPositionTicks: nil,
                playedPercentage: nil,
                isFavorite: nil,
                played: played
            ),
            providerIds: nil
        )
    }

    func testResumeItemGetsNextEpisodeBadge() {
        let item = makeItem(id: "r1")
        XCTAssertEqual(
            CardBadge.badge(for: item, resumeItems: ["r1"]),
            .nextEpisode(day: nil)
        )
    }

    func testUnwatchedSeriesGetsNewSeasonBadge() {
        let item = makeItem(id: "s1", type: "Series", played: false)
        XCTAssertEqual(CardBadge.badge(for: item, resumeItems: []), .newSeason)
    }

    func testUnwatchedMovieGetsNoBadge() {
        let item = makeItem(id: "m1", type: "Movie", played: false)
        XCTAssertNil(CardBadge.badge(for: item, resumeItems: []))
    }

    func testWatchedSeriesGetsNoBadge() {
        let item = makeItem(id: "s2", type: "Series", played: true)
        XCTAssertNil(CardBadge.badge(for: item, resumeItems: []))
    }

    func testResumeTakesPrecedenceOverSeriesBadge() {
        let item = makeItem(id: "s3", type: "Series", played: false)
        XCTAssertEqual(
            CardBadge.badge(for: item, resumeItems: ["s3"]),
            .nextEpisode(day: nil)
        )
    }
}
