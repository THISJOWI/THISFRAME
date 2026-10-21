import SwiftUI

/// Motion tokens. One place decides how the app moves, so every transition
/// feels like the same product.
///
/// Every curve here is short and settled: nothing bounces, nothing lasts
/// longer than half a second.
enum MareaMotion {
    /// Small state changes (button presses, selection tints).
    static let quick = Animation.easeInOut(duration: 0.18)
    /// Standard enter/exit (cards, panels, sheets).
    static let standard = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// Large, soft movement (rows appearing).
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.86)
    /// Opacity-only changes (images, loading states).
    static let fade = Animation.easeOut(duration: 0.22)
    /// Progress fills move a little longer than a state change — the eye
    /// follows the bar to its new position.
    static let easeOutProgress = Animation.easeOut(duration: 0.35)

    /// The curve to apply, honouring the system's "reduce motion" setting.
    ///
    /// `nil` means "animate nothing" — SwiftUI reads a `nil` animation as
    /// "no implicit animation", which is exactly what the system asks for.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Applies a motion token only when the system allows animation.
struct MareaMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(
            MareaMotion.resolve(animation, reduceMotion: reduceMotion),
            value: value
        )
    }
}

extension View {
    /// Animates `value` changes with a motion token, unless the user asked
    /// the system to reduce motion.
    func mareaAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MareaMotionModifier(animation: animation, value: value))
    }
}
