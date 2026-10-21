#if os(macOS)
import AppKit
import ThisJellyFixCore

/// The AppKit appearance that matches an appearance preference.
///
/// macOS resolves dynamic colors (`NSColor(name:dynamicProvider:)`) against
/// `NSAppearance`, NOT against SwiftUI's color scheme. A forced light/dark
/// mode therefore has to set the app appearance too — otherwise the theme
/// tokens keep resolving the dark variant while the system text turns
/// black: unreadable pages.
enum MacAppearance {
    /// The appearance to apply, or `nil` to follow the system.
    static func appAppearance(for mode: AppearanceSettings.Appearance) -> NSAppearance? {
        switch mode {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}
#endif
