import XCTest
import SwiftUI
@testable import ThisJellyFixFeature

final class MareaThemeTests: XCTestCase {
    func testBackgroundIsPureBlack() {
        XCTAssertEqual(MareaTheme.Colors.background, Color.black)
    }

    func testAccentMatchesBadgeRed() {
        XCTAssertEqual(MareaTheme.Colors.accent, MareaTheme.Colors.badgeRed)
    }

    func testSpacingScale() {
        XCTAssertEqual(MareaTheme.Spacing.xs, 4)
        XCTAssertEqual(MareaTheme.Spacing.sm, 8)
        XCTAssertEqual(MareaTheme.Spacing.md, 16)
        XCTAssertEqual(MareaTheme.Spacing.lg, 24)
        XCTAssertEqual(MareaTheme.Spacing.xl, 32)
    }

    func testRadii() {
        XCTAssertEqual(MareaTheme.Radius.small, 8)
        XCTAssertEqual(MareaTheme.Radius.card, 12)
        XCTAssertEqual(MareaTheme.Radius.hero, 24)
    }
}
