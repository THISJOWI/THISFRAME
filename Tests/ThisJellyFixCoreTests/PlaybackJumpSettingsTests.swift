import XCTest
@testable import ThisJellyFixCore

/// Outline: "Retroceso/avance: poder elegir el tiempo de salto".
/// The transport must never receive a distance without a matching SF Symbol
/// (`gobackward.10` … `goforward.90`), so stored values are always validated.
final class PlaybackJumpSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PlaybackJumpSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshInstallUsesDefaults() {
        let settings = PlaybackJumpSettings.current(defaults)
        XCTAssertEqual(settings.backwardSeconds, 15)
        XCTAssertEqual(settings.forwardSeconds, 30)
    }

    func testStoredValidValuesAreHonored() {
        defaults.set(10, forKey: PlaybackJumpSettings.Key.backward)
        defaults.set(90, forKey: PlaybackJumpSettings.Key.forward)

        let settings = PlaybackJumpSettings.current(defaults)

        XCTAssertEqual(settings.backwardSeconds, 10)
        XCTAssertEqual(settings.forwardSeconds, 90)
    }

    func testStaleStoredValueFallsBackToDefault() {
        // A number outside the supported set (older build, manual edit) must
        // not produce a missing symbol in the transport.
        defaults.set(7, forKey: PlaybackJumpSettings.Key.backward)
        defaults.set(3600, forKey: PlaybackJumpSettings.Key.forward)

        let settings = PlaybackJumpSettings.current(defaults)

        XCTAssertEqual(settings.backwardSeconds, PlaybackJumpSettings.defaultBackward)
        XCTAssertEqual(settings.forwardSeconds, PlaybackJumpSettings.defaultForward)
    }

    func testInitValidatesBothAxes() {
        let settings = PlaybackJumpSettings(backwardSeconds: 42, forwardSeconds: 15)
        XCTAssertEqual(settings.backwardSeconds, PlaybackJumpSettings.defaultBackward)
        XCTAssertEqual(settings.forwardSeconds, 15)
    }

    func testEveryOptionIsSelectableAsStoredValue() {
        for seconds in PlaybackJumpSettings.allowedSeconds {
            XCTAssertEqual(PlaybackJumpSettings.validated(seconds), seconds)
        }
    }
}
