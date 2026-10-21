import SwiftUI

/// A thin progress line: a track plus a filled share of it.
///
/// Used by the episode rows and the "continue watching" card. The fill keeps
/// the brand accent so it never reads as a decorative rule.
struct ProgressBarView: View {
    /// Played share in `0...1`.
    let fraction: Double
    var height: CGFloat = 3
    /// Channel of the bar. Cards that draw it on top of artwork pass a dark
    /// scrim; bars on the page use the theme token.
    var track: Color = MareaTheme.Colors.progressTrack

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Capsule()
                    .fill(MareaTheme.Colors.accent)
                    .frame(width: max(0, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .mareaAnimation(MareaMotion.easeOutProgress, value: clamped)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        ProgressBarView(fraction: 0)
        ProgressBarView(fraction: 0.45)
        ProgressBarView(fraction: 1)
    }
    .padding(24)
    .background(MareaTheme.Colors.background)
}
