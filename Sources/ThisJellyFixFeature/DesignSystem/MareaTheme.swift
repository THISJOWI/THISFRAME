import SwiftUI

/// Design tokens for La Marea. Single source of truth — no raw colors,
/// spacing or corner radii outside `DesignSystem`.
enum MareaTheme {
    /// Raw palette. Both variants of every token live here so the values are
    /// testable without a view, and the DARK variant is the historical one:
    /// the dark theme of THISFRAME must not change.
    enum Palette {
        static let backgroundDark = Color.black
        static let backgroundLight = Color(white: 0.97)

        static let surfaceDark = Color(red: 0.11, green: 0.11, blue: 0.12)
        static let surfaceLight = Color(white: 1.0)

        static let surfaceElevatedDark = Color(red: 0.16, green: 0.16, blue: 0.18)
        static let surfaceElevatedLight = Color(white: 0.93)

        static let glassDark = Color.white.opacity(0.08)
        static let glassLight = Color.black.opacity(0.06)

        static let borderGlowDark = Color.white.opacity(0.18)
        static let borderGlowLight = Color.black.opacity(0.12)

        /// Brand red. Identical in both variants — the identity never moves.
        static let accent = Color(red: 0.90, green: 0.06, blue: 0.13)
        static let accentLight = accent
        static let accentDark = accent

        /// The brand red used as TEXT on the page background.
        ///
        /// The brand red itself reaches 4.44:1 on the dark background and
        /// 4.43:1 on the light one — just under the 4.5:1 of WCAG AA. The
        /// TEXT variant is the SAME hue, tuned a shade per mode so it clears
        /// AA in both: a shade deeper on light, a shade lighter on dark.
        ///
        /// Fills — buttons, progress bars, badges — keep the brand red
        /// untouched, in both modes.
        static let accentTextLight = Color(red: 0.83, green: 0.045, blue: 0.11)
        static let accentTextDark = Color(red: 0.93, green: 0.10, blue: 0.16)

        static let badgeNeutralDark = Color(red: 0.25, green: 0.27, blue: 0.32)
        static let badgeNeutralLight = Color(white: 0.35)

        static let heroFallbackDark = Color(red: 0.08, green: 0.10, blue: 0.18)
        static let heroFallbackLight = Color(white: 0.88)
    }

    enum Colors {
        /// App background — content provides the color (Netflix-style home).
        static let background = Color.adaptive(
            light: Palette.backgroundLight,
            dark: Palette.backgroundDark
        )
        /// Card / surface on top of the background.
        static let surface = Color.adaptive(
            light: Palette.surfaceLight,
            dark: Palette.surfaceDark
        )
        /// Elevated surface (panels, sheets).
        static let surfaceElevated = Color.adaptive(
            light: Palette.surfaceElevatedLight,
            dark: Palette.surfaceElevatedDark
        )
        /// Translucent fill for chips, glass panels and the floating tab bar.
        static let glass = Color.adaptive(
            light: Palette.glassLight,
            dark: Palette.glassDark
        )
        /// Hairline glow border for focused/hovered cards.
        static let borderGlow = Color.adaptive(
            light: Palette.borderGlowLight,
            dark: Palette.borderGlowDark
        )
        /// Red used for badges and "new season" flags.
        static let badgeRed = Color.adaptive(
            light: Palette.accentLight,
            dark: Palette.accentDark
        )
        /// Neutral slate for "Recién añadido" — visible without shouting.
        static let badgeNeutral = Color.adaptive(
            light: Palette.badgeNeutralLight,
            dark: Palette.badgeNeutralDark
        )
        /// Unified accent — tint, progress bars, active tab.
        static let accent = badgeRed
        /// The accent when it is used as TEXT on the page background.
        static let accentText = Color.adaptive(
            light: Palette.accentTextLight,
            dark: Palette.accentTextDark
        )
        /// Fallback backdrop while a hero image loads.
        static let heroFallback = Color.adaptive(
            light: Palette.heroFallbackLight,
            dark: Palette.heroFallbackDark
        )

        // MARK: - Semantic additions
        //
        // These replace the literal colors that used to be scattered across
        // the views. Same role, one place.

        /// Translucent fill for settings panels and cards over the background.
        static let overlayFill = Color.adaptive(
            light: Color.black.opacity(0.05),
            dark: Color.white.opacity(0.05)
        )
        /// Fill for a screen background that sits above the app background.
        static let surfaceOverlay = Color.adaptive(
            light: Color.black.opacity(0.03),
            dark: Color.black.opacity(0.3)
        )
        /// Scrim behind text placed on top of artwork.
        static let scrim = Color.adaptive(
            light: Color.black.opacity(0.45),
            dark: Color.black.opacity(0.55)
        )
        /// Channel of a progress bar (the unfilled part).
        static let progressTrack = Color.adaptive(
            light: Color.black.opacity(0.18),
            dark: Color.white.opacity(0.25)
        )
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let card: CGFloat = 12
        static let hero: CGFloat = 24
    }
}
