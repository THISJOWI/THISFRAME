import XCTest
import SwiftUI
@testable import ThisJellyFixFeature

final class MareaThemeTests: XCTestCase {
    func testBackgroundIsPureBlack() {
        // The DARK variant must stay exactly the historical one: THISFRAME's
        // identity is a pure black app with a brand red.
        XCTAssertEqual(MareaTheme.Palette.backgroundDark, Color.black)
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

    func testDarkAccentKeepsCrimsonFrame() {
        XCTAssertEqual(
            MareaTheme.Palette.accentDark,
            MareaTheme.Palette.crimsonFrame
        )
        XCTAssertEqual(
            MareaTheme.Palette.crimsonFrame,
            Color(red: 0.851, green: 0.212, blue: 0.310)
        )
    }

    func testCrimsonFrameIsTheSingleBrandAccent() {
        // Every brand token resolves to the same value: one definition.
        XCTAssertEqual(MareaTheme.Colors.crimsonFrame, MareaTheme.Colors.accent)
        XCTAssertEqual(MareaTheme.Colors.accent, MareaTheme.Colors.badgeRed)
        XCTAssertEqual(MareaTab.home.activeColor, MareaTheme.Colors.crimsonFrame)
    }

    func testAccentIsIdenticalInLightAndDark() {
        // The brand red never moves: it is the one color of the identity.
        XCTAssertEqual(MareaTheme.Palette.accentLight, MareaTheme.Palette.accentDark)
    }

    func testEverySurfaceTokenDefinesBothVariants() {
        XCTAssertNotEqual(MareaTheme.Palette.backgroundLight, MareaTheme.Palette.backgroundDark)
        XCTAssertNotEqual(MareaTheme.Palette.surfaceLight, MareaTheme.Palette.surfaceDark)
        XCTAssertNotEqual(
            MareaTheme.Palette.surfaceElevatedLight,
            MareaTheme.Palette.surfaceElevatedDark
        )
    }
}
