import XCTest
@testable import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

/// Scriptable library client — feeds `load()` with fixed rows.
final class StubLibraryClient: JellyfinLibraryProviding, @unchecked Sendable {
    var views: [LibraryView] = []
    var resumeItems: [JellyfinMediaItem] = []
    var latestItems: [JellyfinMediaItem] = []
    private(set) var recordedStartIndices: [Int?] = []

    func fetchViews(userId: String, serverURL: URL, token: String) async throws -> [LibraryView] {
        views
    }

    func fetchItems(
        userId: String, serverURL: URL, token: String,
        parentId: String?, includeTypes: String?,
        limit: Int, orderBy: String, filters: String?, startIndex: Int?
    ) async throws -> [JellyfinMediaItem] {
        recordedStartIndices.append(startIndex)
        return latestItems
    }

    func searchItems(
        userId: String, serverURL: URL, token: String,
        query: String, includeTypes: String?, limit: Int
    ) async throws -> [JellyfinMediaItem] {
        []
    }

    func fetchSeasons(userId: String, serverURL: URL, token: String, seriesId: String) async throws -> [JellyfinSeason] {
        []
    }

    func fetchEpisodes(
        userId: String, serverURL: URL, token: String,
        seriesId: String, seasonId: String
    ) async throws -> [JellyfinEpisode] {
        []
    }

    func fetchResumeItems(userId: String, serverURL: URL, token: String, limit: Int) async throws -> [JellyfinMediaItem] {
        resumeItems
    }
}

@MainActor
final class LibraryModelHeroTests: XCTestCase {
    private let serverURL = URL(string: "http://localhost:8096")!

    func makeItem(id: String, name: String) -> JellyfinMediaItem {
        JellyfinMediaItem(
            id: id, name: name, type: "Movie", overview: nil, seriesName: nil,
            indexNumber: nil, parentIndexNumber: nil, year: nil, imageTags: nil,
            backdropImageTags: nil, officialRating: nil, communityRating: nil,
            genres: nil, userData: nil, providerIds: nil
        )
    }

    func testHeroItemsPrioritizeResumeThenLatestUpToFive() async {
        let stub = StubLibraryClient()
        stub.resumeItems = (1...3).map { makeItem(id: "r\($0)", name: "Resume \($0)") }
        stub.latestItems = (1...5).map { makeItem(id: "l\($0)", name: "Latest \($0)") }
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        await model.load()

        let heroes = model.heroItems
        XCTAssertEqual(heroes.count, 5)
        XCTAssertEqual(heroes.prefix(3).map(\.id), ["r1", "r2", "r3"])
        XCTAssertEqual(heroes.suffix(2).map(\.id), ["l1", "l2"])
    }

    func testHeroItemsDeduplicates() async {
        let stub = StubLibraryClient()
        let shared = makeItem(id: "x1", name: "Shared")
        stub.resumeItems = [shared]
        stub.latestItems = [shared, makeItem(id: "l2", name: "Latest 2")]
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        await model.load()

        let ids = model.heroItems.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids.filter { $0 == "x1" }.count, 1)
    }

    func testHeroItemsEmptyWithoutRows() {
        let stub = StubLibraryClient()
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        XCTAssertTrue(model.heroItems.isEmpty)
    }
}
