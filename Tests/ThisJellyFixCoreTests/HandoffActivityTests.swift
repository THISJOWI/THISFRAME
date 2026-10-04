import XCTest
@testable import ThisJellyFixCore

/// T4 — publication side: one owner for the playback activity, a browsing
/// activity that yields while playing, and a complete payload (the Mac can
/// tell WHAT to continue and WHERE it belongs).
final class HandoffActivityTests: XCTestCase {
    private let item = HandoffMediaItem(id: "abc", name: "Episodio 1", type: "Episode")
    private let server = URL(string: "https://jellyfin.example.com")!

    func testPlayingActivityCarriesFullPayload() throws {
        let activity = HandoffActivity.playingActivity(
            item: item, serverURL: server, userId: "user-1", position: 42.5
        )
        XCTAssertEqual(activity.activityType, HandoffActivity.playing)
        XCTAssertTrue(activity.isEligibleForHandoff)
        XCTAssertFalse(activity.isEligibleForSearch)

        let info = try XCTUnwrap(activity.userInfo)
        XCTAssertEqual(info[HandoffActivity.Key.itemId] as? String, "abc")
        XCTAssertEqual(info[HandoffActivity.Key.serverURL] as? String, server.absoluteString)
        XCTAssertEqual(info[HandoffActivity.Key.title] as? String, "Episodio 1")
        XCTAssertEqual(info[HandoffActivity.Key.mediaType] as? String, "Episode")
        XCTAssertEqual(info[HandoffActivity.Key.userId] as? String, "user-1")
        XCTAssertEqual(info[HandoffActivity.Key.position] as? Double, 42.5)
    }

    func testPlayingActivityDeclaresRequiredKeysAndTarget() {
        let activity = HandoffActivity.playingActivity(
            item: item, serverURL: server, userId: "user-1", position: 42.5
        )
        // Without requiredUserInfoKeys the system may deliver the activity
        // with userInfo stripped (cold launch receives an EMPTY payload).
        // `title` is required too: the receiving guard demands it.
        XCTAssertEqual(
            activity.requiredUserInfoKeys,
            [HandoffActivity.Key.itemId, HandoffActivity.Key.serverURL,
             HandoffActivity.Key.title, HandoffActivity.Key.position,
             HandoffActivity.Key.userId]
        )
        // targetContentIdentifier lets the system route the continuation to
        // the right window/scene instead of just launching the app.
        XCTAssertEqual(
            activity.targetContentIdentifier,
            "\(server.absoluteString)/\(HandoffActivity.Key.itemId)/abc"
        )
    }

    func testDetailActivityCarriesPayloadAndTarget() {
        let activity = HandoffActivity.detailActivity(item: item, serverURL: server)
        XCTAssertEqual(activity.activityType, HandoffActivity.detail)
        XCTAssertTrue(activity.isEligibleForHandoff)
        XCTAssertEqual(
            activity.requiredUserInfoKeys,
            [HandoffActivity.Key.itemId, HandoffActivity.Key.serverURL,
             HandoffActivity.Key.title, HandoffActivity.Key.mediaType]
        )
        XCTAssertNotNil(activity.targetContentIdentifier)
        XCTAssertNil(activity.userInfo?[HandoffActivity.Key.position])
    }

    /// The PlayerView publication closure copies fields off a throwaway
    /// `built` activity — those two must survive the copy or the continuation
    /// never routes to the right scene (M3).
    func testBuiltActivityCarriesEverythingTheClosureMustCopy() {
        let built = HandoffActivity.playingActivity(
            item: item, serverURL: server, userId: "user-1", position: 42.5
        )
        XCTAssertNotNil(built.requiredUserInfoKeys)
        XCTAssertNotNil(built.targetContentIdentifier)
    }

    /// F5: position/userId ride in requiredUserInfoKeys — if the system
    /// strips them in transit the receiver silently degrades to server-resume.
    func testPlayingActivityRequiresPositionAndUser() {
        let activity = HandoffActivity.playingActivity(
            item: item, serverURL: server, userId: "user-1", position: 42.5
        )
        XCTAssertEqual(
            activity.requiredUserInfoKeys,
            [HandoffActivity.Key.itemId, HandoffActivity.Key.serverURL,
             HandoffActivity.Key.title, HandoffActivity.Key.position,
             HandoffActivity.Key.userId]
        )
    }
}
