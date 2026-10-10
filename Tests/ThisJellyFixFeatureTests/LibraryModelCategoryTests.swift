import XCTest
@testable import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

@MainActor
final class LibraryModelCategoryTests: XCTestCase {
    private let serverURL = URL(string: "http://localhost:8096")!

    func testCategoryChipsFromServerViews() async {
        let stub = StubLibraryClient()
        stub.views = [
            LibraryView(id: "mv", name: "Películas", collectionType: "movies"),
            LibraryView(id: "tv", name: "Series", collectionType: "tvshows"),
        ]
        stub.latestItems = []
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        await model.load()

        let chips = model.categoryChips
        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0].id, "Películas")
        XCTAssertEqual(chips[0].parentId, "mv")
        XCTAssertEqual(chips[0].includeTypes, "Movie")
        XCTAssertEqual(chips[1].id, "Series")
        XCTAssertEqual(chips[1].parentId, "tv")
        XCTAssertEqual(chips[1].includeTypes, "Series")
    }

    func testCategoryChipsEmptyWithoutViews() async {
        let stub = StubLibraryClient()
        stub.views = []
        stub.latestItems = []
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        await model.load()

        XCTAssertTrue(model.categoryChips.isEmpty)
    }
}
