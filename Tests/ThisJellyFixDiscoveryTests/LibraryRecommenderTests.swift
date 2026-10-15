import XCTest
@testable import ThisJellyFixDiscovery
@testable import ThisJellyFixCore

/// P10: local recommendations are deterministic, explainable and grounded —
/// never random picks dressed as intelligence.
final class LibraryRecommenderTests: XCTestCase {
    private func item(
        _ id: String,
        name: String,
        genres: [String] = [],
        rating: Double? = nil,
        played: Bool? = nil,
        favorite: Bool? = nil,
        percentage: Double? = nil
    ) -> JellyfinMediaItem {
        var ud: [String] = []
        if let played { ud.append("\"Played\":\(played ? "true" : "false")") }
        if let favorite { ud.append("\"IsFavorite\":\(favorite ? "true" : "false")") }
        if let percentage { ud.append("\"PlayedPercentage\":\(percentage)") }
        let userData = ud.isEmpty ? "null" : "{" + ud.joined(separator: ",") + "}"
        let genresJSON = genres.map({ "\"" + $0 + "\"" }).joined(separator: ",")
        let ratingJSON = rating.map({ String($0) }) ?? "null"
        let json = "{\"Id\":\"" + id + "\",\"Name\":\"" + name
            + "\",\"Type\":\"Movie\",\"Genres\":[" + genresJSON
            + "],\"CommunityRating\":" + ratingJSON
            + ",\"UserData\":" + userData + "}"
        return try! JSONDecoder().decode(JellyfinMediaItem.self, from: Data(json.utf8))
    }

    func testExcludesWatchedInProgressAndFavorites() {
        let library = [
            item("w", name: "Watched", genres: ["Drama"], played: true),
            item("p", name: "InProgress", genres: ["Drama"], percentage: 50),
            item("f", name: "Fav", genres: ["Drama"], favorite: true),
            item("n", name: "Fresh Drama", genres: ["Drama"]),
        ]
        let result = LibraryRecommender.recommend(from: library)
        XCTAssertEqual(result.map(\.item.id), ["n"])
    }

    func testGenreAffinityOrdersCandidates() {
        let library = [
            item("s1", name: "SciFi Hit", genres: ["Sci-Fi"], played: true),
            item("s2", name: "SciFi Hit 2", genres: ["Sci-Fi"], played: true),
            item("d1", name: "Drama Hit", genres: ["Drama"], played: true),
            item("cs", name: "Fresh SciFi", genres: ["Sci-Fi"]),
            item("cd", name: "Fresh Drama", genres: ["Drama"]),
        ]
        let result = LibraryRecommender.recommend(from: library)
        XCTAssertEqual(result.map(\.item.id), ["cs", "cd"])
    }

    func testFavoritesWeighMoreThanWatched() {
        let library = [
            item("w", name: "Watched A", genres: ["A"], played: true),
            item("f", name: "Loved B", genres: ["B"], favorite: true),
            item("ca", name: "Fresh A", genres: ["A"]),
            item("cb", name: "Fresh B", genres: ["B"]),
        ]
        let result = LibraryRecommender.recommend(from: library)
        XCTAssertEqual(result.first?.item.id, "cb")
    }

    func testReasonNamesARealWitness() {
        let library = [
            item("s", name: "Dune", genres: ["Sci-Fi"], played: true),
            item("c", name: "Fresh SciFi", genres: ["Sci-Fi"]),
        ]
        let result = LibraryRecommender.recommend(from: library)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].reason.contains("Dune"), "reason must name the real signal, got: \(result[0].reason)")
    }

    func testNoSignalsFallsBackToTopRated() {
        let library = [
            item("a", name: "Meh", genres: ["X"], rating: 5.0),
            item("b", name: "Gem", genres: ["Y"], rating: 9.0),
        ]
        let result = LibraryRecommender.recommend(from: library)
        XCTAssertEqual(result.first?.item.id, "b")
        XCTAssertTrue(result[0].reason.contains("valorado"))
    }

    func testEmptyLibraryYieldsNoRows() {
        XCTAssertTrue(LibraryRecommender.recommend(from: []).isEmpty)
    }

    func testAllWatchedYieldsNoRows() {
        let library = [item("w", name: "Done", genres: ["A"], played: true)]
        XCTAssertTrue(LibraryRecommender.recommend(from: library).isEmpty)
    }

    func testLimitIsRespected() {
        let library = (1...20).map { item("c\($0)", name: "Fresh \($0)", genres: ["G"]) }
        XCTAssertEqual(LibraryRecommender.recommend(from: library, limit: 5).count, 5)
    }

    func testDeterministicOrder() {
        let library = [
            item("s", name: "Hit", genres: ["G"], played: true),
            item("b", name: "Beta", genres: ["G"]),
            item("a", name: "Alpha", genres: ["G"]),
        ]
        let first = LibraryRecommender.recommend(from: library).map(\.item.id)
        let second = LibraryRecommender.recommend(from: library).map(\.item.id)
        XCTAssertEqual(first, second)
        // Same score + same rating → alphabetical.
        XCTAssertEqual(first, ["a", "b"])
    }
}
