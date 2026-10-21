import SwiftUI
import ThisJellyFixCore

/// Shimmering placeholder shown while a card or row loads.
struct SkeletonView: View {
    let width: CGFloat
    let height: CGFloat
    /// When set, the placeholder takes the width its container offers and
    /// derives the height from this ratio — the same box the real card will
    /// occupy, so nothing jumps when the artwork arrives.
    var aspectRatio: CGFloat? = nil
    var cornerRadius: CGFloat = MareaTheme.Radius.card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmering = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(MareaTheme.Colors.surface)
            .overlay(
                // Subtle sheen sweeping across the placeholder.
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.06), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: shimmering && !reduceMotion ? width : -width)
            )
            .modifier(SkeletonSizing(width: width, height: height, aspectRatio: aspectRatio))
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shimmering = true
                }
            }
    }
}

/// Fixed box, or a ratio box that follows the container width.
private struct SkeletonSizing: ViewModifier {
    let width: CGFloat
    let height: CGFloat
    let aspectRatio: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let aspectRatio {
            content
                .frame(maxWidth: .infinity)
                .aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            content
                .frame(width: width, height: height)
        }
    }
}

/// A title bar plus a row of card skeletons — the Home loading state.
struct SkeletonRowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MareaTheme.Spacing.sm) {
            RoundedRectangle(cornerRadius: MareaTheme.Radius.small / 2)
                .fill(MareaTheme.Colors.surface)
                .frame(width: 160, height: 20)
                .padding(.horizontal, MareaTheme.Spacing.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonView(width: 150, height: 220)
                    }
                }
                .padding(.horizontal, MareaTheme.Spacing.xl)
            }
        }
    }
}

#Preview {
    SkeletonRowView()
        .padding(.vertical)
        .background(MareaTheme.Colors.background)
}
