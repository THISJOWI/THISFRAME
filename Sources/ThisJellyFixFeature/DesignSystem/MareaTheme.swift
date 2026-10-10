import SwiftUI

/// Design tokens for La Marea. Single source of truth — no raw colors,
/// spacing or corner radii outside `DesignSystem`.
enum MareaTheme {
    enum Colors {
        /// Pure black background — content provides the color (Netflix-style home).
        static let background = Color.black
        /// Card / surface on top of the background.
        static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
        /// Elevated surface (panels, sheets).
        static let surfaceElevated = Color(red: 0.16, green: 0.16, blue: 0.18)
        /// Translucent fill for chips, glass panels and the floating tab bar.
        static let glass = Color.white.opacity(0.08)
        /// Hairline glow border for focused/hovered cards.
        static let borderGlow = Color.white.opacity(0.18)
        /// Red used for badges and "new season" flags.
        static let badgeRed = Color(red: 0.90, green: 0.06, blue: 0.13)
        /// Unified accent — tint, progress bars, active tab.
        static let accent = badgeRed
        /// Fallback backdrop while a hero image loads.
        static let heroFallback = Color(red: 0.08, green: 0.1, blue: 0.18)
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
