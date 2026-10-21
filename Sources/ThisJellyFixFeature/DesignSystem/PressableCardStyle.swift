import SwiftUI

/// Press feedback for a poster card: the card shrinks a touch while the
/// finger is down and settles back on release.
struct PressableCardStyle: ButtonStyle {
    /// Scale applied while pressed.
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(MareaMotion.quick, value: configuration.isPressed)
    }
}
