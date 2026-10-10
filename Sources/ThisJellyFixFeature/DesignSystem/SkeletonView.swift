import SwiftUI

/// Shimmering placeholder shown while a card or row loads.
struct SkeletonView: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = MareaTheme.Radius.card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmering = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(MareaTheme.Colors.surface)
            .overlay(
                // Subtle sheen sweeping across the placeholder.
                LinearGradient(
                    colors: [.clear, .white.opacity(0.06), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: shimmering && !reduceMotion ? width : -width)
            )
            .frame(width: width, height: height)
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shimmering = true
                }
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
