import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixCore
import ThisJellyFixNetworking

/// P7: in-player favorite reflects the SERVER flag and toggles it —
/// never a local-only state contradicting Jellyfin.
@MainActor
final class PlayerViewModelFavoriteTests: XCTestCase {
    private func makeVM(
        favorite: Bool = false,
        actionError: Error? = nil
    ) -> (PlayerViewModel, StubUserActionClient) {
        let vm = PlayerViewModel()
        let actions = StubUserActionClient(error: actionError)
        vm.userActionClient = actions
        vm.itemDetailClient = StubItemDetailClient(favorite: favorite)
        vm.configureReporting(
            userId: "u1",
            serverURL: URL(string: "http://localhost:1")!,
            token: "tok",
            itemId: "item-1"
        )
        return (vm, actions)
    }

    func testLoadReadsServerFlag() async {
        let (vm, _) = makeVM(favorite: true)
        let ok = await vm.loadFavoriteState()
        XCTAssertTrue(ok)
        XCTAssertTrue(vm.isFavorite)
        XCTAssertTrue(vm.isFavoriteKnown)
    }

    func testToggleSetsFavoriteOnServer() async {
        let (vm, actions) = makeVM(favorite: false)
        await vm.toggleFavorite()
        XCTAssertTrue(vm.isFavorite)
        XCTAssertEqual(actions.calls, [true])
        XCTAssertNil(vm.favoriteError)
    }

    func testToggleRollsBackOnFailure() async {
        let (vm, actions) = makeVM(favorite: false, actionError: LibraryError.serverError(500))
        await vm.toggleFavorite()
        XCTAssertFalse(vm.isFavorite, "rollback must restore the server truth")
        XCTAssertEqual(actions.calls, [true])
        XCTAssertNotNil(vm.favoriteError)
    }

    func testToggleUnsetsFavorite() async {
        let (vm, actions) = makeVM(favorite: true)
        await vm.toggleFavorite()
        XCTAssertFalse(vm.isFavorite)
        XCTAssertEqual(actions.calls, [false])
    }

    func testToggleWithoutServerFlagRefusesBlindFlip() async {
        let vm = PlayerViewModel()
        let actions = StubUserActionClient(error: nil)
        vm.userActionClient = actions
        vm.itemDetailClient = StubItemDetailClient(error: LibraryError.unauthorized)
        vm.configureReporting(
            userId: "u1",
            serverURL: URL(string: "http://localhost:1")!,
            token: "tok",
            itemId: "item-1"
        )
        await vm.toggleFavorite()
        XCTAssertTrue(actions.calls.isEmpty, "must not write without knowing the truth")
        XCTAssertNotNil(vm.favoriteError)
    }
}

// MARK: - Stubs

private final class StubUserActionClient: JellyfinUserActionProviding, @unchecked Sendable {
    let error: Error?
    private(set) var calls: [Bool] = []

    init(error: Error? = nil) { self.error = error }

    func setFavorite(_ favorite: Bool, userId: String, serverURL: URL, token: String, itemId: String) async throws {
        calls.append(favorite)
        if let error { throw error }
    }

    func setPlayed(_ played: Bool, userId: String, serverURL: URL, token: String, itemId: String) async throws {
        if let error { throw error }
    }
}

private final class StubItemDetailClient: JellyfinItemDetailProviding, @unchecked Sendable {
    let favorite: Bool
    let error: Error?

    init(favorite: Bool = false, error: Error? = nil) {
        self.favorite = favorite
        self.error = error
    }

    func fetchItemDetail(userId: String, serverURL: URL, token: String, itemId: String) async throws -> JellyfinItemDetail {
        if let error { throw error }
        let json = """
        {"Id":"\(itemId)","Name":"N","Type":"Movie","UserData":{"IsFavorite":\(favorite ? "true" : "false")}}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(JellyfinItemDetail.self, from: json)
    }
}
