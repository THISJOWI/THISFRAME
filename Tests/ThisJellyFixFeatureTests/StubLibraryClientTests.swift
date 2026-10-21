import XCTest
@testable import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

/// `LibraryModel.load()` fetches its rows CONCURRENTLY, so the stub is hit
/// from several threads at once. It has to survive that.
final class StubLibraryClientTests: XCTestCase {
    private let serverURL = URL(string: "http://localhost:8096")!

    func testConcurrentFetchItemsRecordsEveryStartIndex() async {
        let stub = StubLibraryClient()
        let calls = 200

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<calls {
                group.addTask {
                    _ = try? await stub.fetchItems(
                        userId: "u1",
                        serverURL: self.serverURL,
                        token: "tok",
                        parentId: nil,
                        includeTypes: nil,
                        limit: 10,
                        orderBy: "DateCreated",
                        filters: nil,
                        startIndex: index
                    )
                }
            }
        }

        XCTAssertEqual(stub.recordedStartIndices.count, calls)
    }
}
