import XCTest
@testable import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

/// Regression for the Outline report "Series: al eliminar una serie no
/// desaparece de la app".
///
/// The app has no live deletion feed — the contract is that every re-read of
/// the library (`load()`, triggered by pull-to-refresh and by returning to the
/// foreground) rebuilds the folder-backed rows from the server response, so an
/// item deleted server-side vanishes instead of surviving in a stale row.
@MainActor
final class LibraryModelDeletionTests: XCTestCase {
    private let serverURL = URL(string: "http://localhost:8096")!

    private func series(_ id: String, _ name: String) -> JellyfinMediaItem {
        JellyfinMediaItem(id: id, name: name, type: "Series")
    }

    func testSeriesDeletedOnServerDisappearsAfterReload() async {
        let stub = StubLibraryClient()
        stub.views = [LibraryView(id: "tv", name: "Series", collectionType: "tvshows")]
        stub.latestItems = [series("s1", "Alpha"), series("s2", "Beta")]
        let model = LibraryModel(
            libraryClient: stub, serverURL: serverURL, userId: "u1", token: "tok"
        )

        await model.load()
        XCTAssertEqual(
            Set(model.rows.first { $0.title == "Series" }?.items.map(\.id) ?? []),
            ["s1", "s2"]
        )

        // The server no longer returns s1 (deleted from another client).
        stub.latestItems = [series("s2", "Beta")]
        await model.load()

        let refreshed = model.rows.first { $0.title == "Series" }
        XCTAssertEqual(
            refreshed?.items.map(\.id), ["s2"],
            "a series removed on the server must not survive a library reload"
        )
        XCTAssertFalse(
            model.allItems.contains { $0.id == "s1" },
            "deleted series must not linger in the flattened item pool"
        )
    }
}
