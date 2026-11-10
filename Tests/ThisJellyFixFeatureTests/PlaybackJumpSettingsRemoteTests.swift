import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixCore
import ThisJellyFixPlayback

/// Regression for the Outline report "Retroceso/avance: poder elegir el
/// tiempo de salto".
///
/// The distance is configurable in the player (10–90 s) and the transport,
/// swipe and double-tap honour it — but the lock screen / headphone remote
/// was hardcoded to ±15 s, so the setting did nothing for the most common
/// way of skipping on a phone.
@MainActor
final class PlaybackJumpSettingsRemoteTests: XCTestCase {

    private var defaults: UserDefaults!
    private var previousValues: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        defaults = UserDefaults.standard
        for key in [PlaybackJumpSettings.Key.backward, PlaybackJumpSettings.Key.forward] {
            previousValues[key] = defaults.object(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in previousValues {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        previousValues.removeAll()
        super.tearDown()
    }

    func testRemoteSkipUsesTheConfiguredDistance() {
        defaults.set(60, forKey: PlaybackJumpSettings.Key.backward)
        defaults.set(90, forKey: PlaybackJumpSettings.Key.forward)

        let settings = PlaybackJumpSettings.current(defaults)
        XCTAssertEqual(settings.backwardSeconds, 60)
        XCTAssertEqual(settings.forwardSeconds, 90)
    }

    func testRemoteSkipFallsBackToTheDefaultForAnUnsupportedValue() {
        defaults.set(45, forKey: PlaybackJumpSettings.Key.backward)

        let settings = PlaybackJumpSettings.current(defaults)
        XCTAssertEqual(
            settings.backwardSeconds, PlaybackJumpSettings.defaultBackward,
            "a distance with no matching SF Symbol must fall back to the default"
        )
    }
}
