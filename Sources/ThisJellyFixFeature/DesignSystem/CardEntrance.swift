import SwiftUI

/// Entrance animation for a poster card: it grows into place with a short
/// delay that follows its position in the row, so a shelf reveals itself in
/// order instead of at random.
///
/// The animation runs ONCE, when the row it belongs to first appears. A card
/// created later — the user scrolled to it — is already in place: it must
/// not animate, or the list flickers while scrolling.
struct CardEntranceModifier: ViewModifier {
    /// Position in the row — drives the delay.
    let index: Int
    /// False when the card must appear without animating.
    let animates: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed: Bool
    /// A card only ever animates once.
    @State private var hasRevealed = false

    init(index: Int, animates: Bool) {
        self.index = index
        self.animates = animates
        // A card that must not animate starts already in place: it is drawn
        // at full size from the first frame, so it never flashes.
        _isRevealed = State(initialValue: !animates)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isRevealed ? 1 : 0.94)
            .opacity(isRevealed ? 1 : 0)
            .onAppear {
                guard !hasRevealed else { return }
                hasRevealed = true
                // Reduced motion, or a card that appears later in the row:
                // show it, do not move it.
                guard animates, !reduceMotion else {
                    isRevealed = true
                    return
                }
                // Capped so the last card of a long row is not late.
                let delay = min(Double(index) * 0.03, 0.2)
                withAnimation(MareaMotion.standard.delay(delay)) {
                    isRevealed = true
                }
            }
    }
}

extension View {
    /// Reveal the view with the card entrance animation.
    ///
    /// - Parameters:
    ///   - index: position in the row, used for the stagger.
    ///   - animates: pass `false` for cards that must appear already in place.
    func cardEntrance(index: Int, animates: Bool = true) -> some View {
        modifier(CardEntranceModifier(index: index, animates: animates))
    }
}
