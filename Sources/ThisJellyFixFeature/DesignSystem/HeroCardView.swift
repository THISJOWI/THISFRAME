import SwiftUI
import ThisJellyFixCore

/// Big featured card at the top of Home — Netflix-style billboard with a
/// backdrop, gradient, "Seguir viendo" flag and a glass info panel.
struct HeroCardView: View {
    let item: JellyfinMediaItem
    /// Landscape backdrop (Thumb/Backdrop frame).
    let backdropURL: URL?
    /// Portrait poster fallback + small poster in the info panel.
    let posterURL: URL?
    /// Tap on "Reproducir" — resume playback.
    let onPlay: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: MareaTheme.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                // Backdrop with a bottom-up gradient for legibility.
                MareaImageView(
                    url: backdropURL ?? posterURL,
                    placeholder: String(item.name.prefix(1)),
                    width: 0,
                    height: 0,
                    fallbackURL: posterURL
                )
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.1), .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                // "Seguir viendo" flag when there is progress.
                if item.playedPercentage != nil {
                    Label("Seguir viendo", systemImage: "play.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, MareaTheme.Spacing.sm)
                        .padding(.vertical, MareaTheme.Spacing.xs)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5))
                        .padding(MareaTheme.Spacing.md)
                }

                VStack {
                    Spacer()
                    heroPanel
                        .padding(MareaTheme.Spacing.md)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.hero))
            .padding(.horizontal, MareaTheme.Spacing.md)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { appeared = true }
        }
    }

    /// Glass panel with poster, title, synopsis, metadata chips, progress and CTA.
    private var heroPanel: some View {
        HStack(alignment: .top, spacing: MareaTheme.Spacing.md) {
            // Small poster
            if let posterURL {
                MareaImageView(url: posterURL, placeholder: "?", width: 84, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.small))
            }

            VStack(alignment: .leading, spacing: MareaTheme.Spacing.xs) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }

                // Metadata chips: rating · year · rating classification
                HStack(spacing: MareaTheme.Spacing.sm) {
                    if let rating = item.communityRating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, MareaTheme.Spacing.sm)
                            .padding(.vertical, MareaTheme.Spacing.xs)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                    if let year = item.year {
                        Text(String(year))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, MareaTheme.Spacing.sm)
                            .padding(.vertical, MareaTheme.Spacing.xs)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                    if let rating = item.officialRating {
                        Text(rating)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, MareaTheme.Spacing.sm)
                            .padding(.vertical, MareaTheme.Spacing.xs)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                }

                // Progress bar
                if let percentage = item.playedPercentage, percentage > 0 {
                    ProgressBar(value: percentage / 100.0)
                        .frame(height: 3)
                        .padding(.top, MareaTheme.Spacing.xs)
                }

                // CTA — white pill, Netflix-style.
                Button(action: onPlay) {
                    Label("Reproducir", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, MareaTheme.Spacing.lg)
                        .padding(.vertical, MareaTheme.Spacing.sm)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, MareaTheme.Spacing.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(MareaTheme.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: MareaTheme.Radius.card)
                .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5)
        )
    }
}

/// Thin progress bar used by the hero panel.
private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(MareaTheme.Colors.accent)
                    .frame(width: max(4, geo.size.width * value))
            }
        }
    }
}
