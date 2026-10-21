import XCTest
@testable import ThisJellyFixCore

/// The appearance preference lives in `UserDefaults` — the same store
/// `@AppStorage` writes to — so the root view can read it live and the
/// choice survives relaunch.
final class AppearanceSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "appearance.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultIsSystem() {
        XCTAssertEqual(AppearanceSettings.current(defaults).appearance, .system)
    }

    func testRoundTripPersistsEachAppearance() {
        for appearance in AppearanceSettings.Appearance.allCases {
            AppearanceSettings(appearance: appearance).save(to: defaults)
            XCTAssertEqual(AppearanceSettings.current(defaults).appearance, appearance)
        }
    }

    func testUnknownStoredValueFallsBackToSystem() {
        defaults.set("nonsense", forKey: AppearanceSettings.Key.appearance)
        XCTAssertEqual(AppearanceSettings.current(defaults).appearance, .system)
    }

    func testAllCasesCoverSystemLightDark() {
        XCTAssertEqual(
            Set(AppearanceSettings.Appearance.allCases),
            [.system, .light, .dark]
        )
    }
}
