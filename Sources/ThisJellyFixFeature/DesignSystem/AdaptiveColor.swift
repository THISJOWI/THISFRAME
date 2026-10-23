import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// A color that resolves to `light` or `dark` with the current color scheme.
    ///
    /// On iOS/tvOS/visionOS the platform resolves the variant against the
    /// trait collection, which SwiftUI derives from the environment's color
    /// scheme — so it follows the app (and the system) live.
    ///
    /// On macOS the resolution follows `NSAppearance`, which is why the app
    /// also keeps `NSApp.appearance` in sync with the user's choice (see
    /// `ThisFrameRootView.applyMacAppearance()`).
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        return dark
        #endif
    }
}
