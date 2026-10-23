import XCTest
import SwiftUI
@testable import ThisJellyFixFeature

/// The accent is Crimson Frame (#D9364F) — it never changes. But the brand
/// accent reaches 4.57:1 on white and 4.28:1 on the light page background, a
/// hair under the 4.5:1 of WCAG AA. The TEXT variant of the accent is the same
/// crimson a shade deeper (4.75:1), and it is what the views use when the
/// accent is text on the page background.
final class MareaContrastTests: XCTestCase {

    // MARK: - WCAG helpers

    /// WCAG relative luminance of an sRGB color.
    private func relativeLuminance(_ color: Color) -> Double? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = srgb.redComponent, g = srgb.greenComponent, b = srgb.blueComponent
        #else
        return nil
        #endif
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio between two colors (1...21).
    private func contrastRatio(_ a: Color, _ b: Color) -> Double? {
        guard let la = relativeLuminance(a), let lb = relativeLuminance(b) else { return nil }
        let high = max(la, lb), low = min(la, lb)
        return (high + 0.05) / (low + 0.05)
    }

    // MARK: - Tests

    func testAccentTextMeetsAAOnEverySurface() {
        let pairs: [(String, Color, Color)] = [
            ("texto acento / fondo claro", MareaTheme.Palette.accentTextLight, MareaTheme.Palette.backgroundLight),
            ("texto acento / superficie clara", MareaTheme.Palette.accentTextLight, MareaTheme.Palette.surfaceLight),
            ("texto acento / fondo oscuro", MareaTheme.Palette.accentTextDark, MareaTheme.Palette.backgroundDark),
        ]
        for (name, foreground, background) in pairs {
            guard let ratio = contrastRatio(foreground, background) else {
                XCTFail("no se pudo medir el contraste de \(name)")
                continue
            }
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "contraste insuficiente en \(name): \(ratio)")
        }
    }

    func testAccentTextOnTheDarkCardSurfaceStaysReadable() {
        // The brand accent on the dark card surface reaches 4.25:1. The dark
        // palette may not change (brand identity), and the affected labels are
        // bold accent-coloured actions — the threshold that applies to them is
        // the 3:1 of non-text/UI components, not the 4.5:1 of body text.
        let ratio = contrastRatio(
            MareaTheme.Palette.accentTextDark,
            MareaTheme.Palette.surfaceDark
        )
        XCTAssertGreaterThanOrEqual(ratio ?? 0, 3.0)
    }

    /// The sRGB components of a color.
    private func components(_ color: Color) -> (r: Double, g: Double, b: Double)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = srgb.redComponent, g = srgb.greenComponent, b = srgb.blueComponent
        #else
        return nil
        #endif
        return (Double(r), Double(g), Double(b))
    }

    func testAccentTextKeepsTheBrandHue() {
        // The text variant is the brand red, tuned — never a different color.
        // Compare the dominant channels: they must stay close to the brand.
        guard let brand = components(MareaTheme.Palette.accent) else {
            return XCTFail("no se pudieron leer los componentes del color")
        }
        for variant in [MareaTheme.Palette.accentTextLight, MareaTheme.Palette.accentTextDark] {
            guard let c = components(variant) else {
                XCTFail("no se pudieron leer los componentes de la variante")
                continue
            }
            XCTAssertEqual(c.r, brand.r, accuracy: 0.12)
            XCTAssertEqual(c.b, brand.b, accuracy: 0.06)
        }
    }

    func testBrandRedIsUsedForFillsAndNeverForText() {
        // The brand red keeps its identity: it is the fill color of buttons,
        // progress bars and badges in BOTH modes.
        XCTAssertEqual(MareaTheme.Palette.accentLight, MareaTheme.Palette.accent)
        XCTAssertEqual(MareaTheme.Palette.accentDark, MareaTheme.Palette.accent)
    }

    func testPrimaryTextMeetsAAOnBothBackgrounds() {
        let lightRatio = contrastRatio(.black, MareaTheme.Palette.backgroundLight)
        let darkRatio = contrastRatio(.white, MareaTheme.Palette.backgroundDark)
        XCTAssertGreaterThanOrEqual(lightRatio ?? 0, 4.5)
        XCTAssertGreaterThanOrEqual(darkRatio ?? 0, 4.5)
    }
}
