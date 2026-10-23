import XCTest
@testable import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

@MainActor
final class LibraryModelPaginationTests: XCTestCase {
    private let serverURL = URL(string: "http://localhost:8096")!

    func testFetchPagePassesStartIndexToClient() async throws {
        let stub = StubLibraryClient()
        stub.latestItems = (1...30).map { i in
            JellyfinMediaItem(
                id: "p\(i)", name: "Item \(i)", type: "Movie", overview: nil,
                seriesName: nil, indexNumber: nil, parentIndexNumber: nil,
                year: nil, imageTags: nil, backdropImageTags: nil,
                officialRating: nil, communityRating: nil, genres: nil,
                userData: nil, providerIds: nil
            )
        }
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        let firstPage = try await model.fetchPage(parentId: "v1", includeTypes: "Movie", limit: 30)

        XCTAssertEqual(firstPage.count, 30)
        let recorded = stub.recordedStartIndices
        XCTAssertEqual(recorded.count, 1)
        XCTAssertNil(recorded[0], "first page must not pass StartIndex")
    }

    func testFetchPageWithStartIndexPaginates() async throws {
        let stub = StubLibraryClient()
        stub.latestItems = (31...45).map { i in
            JellyfinMediaItem(
                id: "p\(i)", name: "Item \(i)", type: "Movie", overview: nil,
                seriesName: nil, indexNumber: nil, parentIndexNumber: nil,
                year: nil, imageTags: nil, backdropImageTags: nil,
                officialRating: nil, communityRating: nil, genres: nil,
                userData: nil, providerIds: nil
            )
        }
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        let secondPage = try await model.fetchPage(
            parentId: "v1", includeTypes: "Movie", limit: 30, startIndex: 30
        )

        XCTAssertEqual(secondPage.count, 15, "partial page signals the end")
        XCTAssertEqual(stub.recordedStartIndices, [30])
    }

    func testFetchPagePropagatesClientErrorInsteadOfReturningEmptyPage() async {
        let stub = StubLibraryClient()
        stub.fetchItemsError = TestError.unavailable
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        do {
            _ = try await model.fetchPage(parentId: "v1", includeTypes: "Movie", limit: 30)
            XCTFail("Expected the page request to preserve its error")
        } catch {
            XCTAssertEqual(error as? TestError, .unavailable)
        }
    }
}

private enum TestError: Error, Equatable {
    case unavailable
}
