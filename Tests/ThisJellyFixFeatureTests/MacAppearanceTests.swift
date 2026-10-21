import XCTest
import SwiftUI
@testable import ThisJellyFixFeature
@testable import ThisJellyFixCore

/// macOS resolves dynamic colors against `NSAppearance`, not against
/// SwiftUI's color scheme. A forced light/dark mode therefore has to set the
/// app appearance as well — otherwise the theme tokens keep resolving the
/// dark variant while the system text turns black: unreadable pages.
final class MacAppearanceTests: XCTestCase {

    func testSystemModeLeavesTheAppearanceToTheSystem() {
        XCTAssertNil(MacAppearance.appAppearance(for: .system))
    }

    func testLightModeUsesTheLightAppearance() {
        let appearance = MacAppearance.appAppearance(for: .light)
        XCTAssertEqual(
            appearance?.bestMatch(from: [.aqua, .darkAqua]),
            .aqua
        )
    }

    func testDarkModeUsesTheDarkAppearance() {
        let appearance = MacAppearance.appAppearance(for: .dark)
        XCTAssertEqual(
            appearance?.bestMatch(from: [.aqua, .darkAqua]),
            .darkAqua
        )
    }

    func testEveryModeResolves() {
        for mode in AppearanceSettings.Appearance.allCases {
            // The call must not trap and must agree with the mode.
            let appearance = MacAppearance.appAppearance(for: mode)
            if mode == .system {
                XCTAssertNil(appearance)
            } else {
                XCTAssertNotNil(appearance)
            }
        }
    }
}
