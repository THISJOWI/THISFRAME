import XCTest
@testable import ThisJellyFixCore

/// T2 — Handoff resolution must NOT consume a pending intent before the
/// library has actually finished loading (cold-launch Dock → app "does
/// nothing" because the payload was dropped against an empty row set).
final class HandoffResolverTests: XCTestCase {
    private let intent = HandoffIntent(
        itemId: "abc",
        serverURL: URL(string: "https://jellyfin.example.com")!,
        title: "Episodio 1",
        mediaType: "Episode",
        position: 123.5
    )

    func testNoIntentIsIdle() {
        XCTAssertEqual(
            HandoffResolver.resolve(intent: nil, library: .loaded(itemCount: 10), itemExists: true),
            .idle
        )
    }

    func testKeepsWaitingWhileLibraryNotLoaded() {
        XCTAssertEqual(
            HandoffResolver.resolve(intent: intent, library: .notLoaded, itemExists: false),
            .keepWaiting("library not loaded")
        )
        XCTAssertEqual(
            HandoffResolver.resolve(intent: intent, library: .notLoaded, itemExists: true),
            .keepWaiting("library not loaded")
        )
    }

    func testNavigatesWhenLibraryLoadedAndItemExists() {
        XCTAssertEqual(
            HandoffResolver.resolve(intent: intent, library: .loaded(itemCount: 42), itemExists: true),
            .navigate
        )
    }

    func testNotFoundOnlyAfterLibraryLoaded() {
        XCTAssertEqual(
            HandoffResolver.resolve(intent: intent, library: .loaded(itemCount: 42), itemExists: false),
            .notFound
        )
    }

    func testIntentRoundTripsPositionAndServer() {
        XCTAssertEqual(intent.position, 123.5)
        XCTAssertEqual(intent.itemId, "abc")
        XCTAssertEqual(intent.mediaType, "Episode")
        XCTAssertEqual(intent.serverURL.host, "jellyfin.example.com")
    }

    // MARK: - Effective start position (Handoff vs server resume)

    func testEffectiveStartUsesHandoffWhenFurther() {
        XCTAssertEqual(HandoffResolver.effectiveStart(handoff: 500, serverResume: 120), 500)
    }

    func testEffectiveStartUsesServerResumeWhenFurther() {
        XCTAssertEqual(HandoffResolver.effectiveStart(handoff: 30, serverResume: 400), 400)
    }

    func testEffectiveStartWithNoHandoffPositionUsesServerResume() {
        XCTAssertEqual(HandoffResolver.effectiveStart(handoff: nil, serverResume: 400), 400)
    }

    func testEffectiveStartWithNothingIsZero() {
        XCTAssertEqual(HandoffResolver.effectiveStart(handoff: nil, serverResume: nil), 0)
    }
}
