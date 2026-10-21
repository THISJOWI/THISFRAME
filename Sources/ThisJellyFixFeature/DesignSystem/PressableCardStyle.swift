import SwiftUI

/// Press feedback for a poster card: the card shrinks a touch while the
/// finger is down and settles back on release.
struct PressableCardStyle: ButtonStyle {
    /// Scale applied while pressed.
    var pressedScale: CGFloat = 0.96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            // Reduced motion: the card still reacts, but it does not move.
            .animation(
                MareaMotion.resolve(MareaMotion.quick, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
