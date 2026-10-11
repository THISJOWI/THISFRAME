import SwiftUI
import ThisJellyFixCore

/// Big featured card at the top of Home — cinematic billboard: full-bleed
/// backdrop, layered gradients for legibility, elegant title block and a
/// single primary CTA. No floating panels: the text sits directly on the
/// artwork, Netflix/Infuse style.
struct HeroCardView: View {
    let item: JellyfinMediaItem
    /// Landscape backdrop (Thumb/Backdrop frame).
    let backdropURL: URL?
    /// Portrait poster used only when the backdrop is missing.
    let posterURL: URL?
    /// Tap on "Reproducir" — resume playback.
    let onPlay: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            gradients
            if item.playedPercentage != nil {
                resumeFlag
            }
            titleBlock
                .padding(MareaTheme.Spacing.lg)
        }
        .frame(height: 430)
        .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.hero))
        .padding(.horizontal, MareaTheme.Spacing.md)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: appeared)
        .onAppear {
            appeared = true
        }
    }

    // MARK: - Pieces

    /// Full-bleed backdrop. A poster fallback is shown aspect-filled and
    /// blurred so a missing 16:9 frame never distorts or letterboxes.
    private var artwork: some View {
        MareaImageView(
            url: backdropURL ?? posterURL,
            placeholder: String(item.name.prefix(1)),
            width: 0,
            height: 0,
            fallbackURL: posterURL
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Legibility layers: bottom-up scrim for the title block, a faint top
    /// scrim so the card blends under the floating nav pill.
    private var gradients: some View {
        ZStack {
            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
    }

    private var resumeFlag: some View {
        Label("Seguir viendo", systemImage: "play.fill")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, MareaTheme.Spacing.sm)
            .padding(.vertical, MareaTheme.Spacing.xs)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 0.5))
            .padding(MareaTheme.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Series eyebrow + title + meta + synopsis + progress + CTA.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: MareaTheme.Spacing.sm) {
            // For episodes the SERIES is the headline; the episode gets a
            // small eyebrow so the billboard reads at a glance.
            if item.type == "Episode" {
                if let seriesName = item.seriesName {
                    Text(seriesName.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MareaTheme.Colors.accent)
                        .tracking(1.2)
                }
                Text(item.episodeLabelAndName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Text(item.name)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

            if hasMetaChips {
                metaChips
            }

            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            }

            if let percentage = item.playedPercentage, percentage > 0 {
                ProgressBar(value: percentage / 100.0)
                    .frame(height: 3)
                    .padding(.top, MareaTheme.Spacing.xs)
            }

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
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var hasMetaChips: Bool {
        item.communityRating != nil || item.year != nil || item.officialRating != nil
    }

    private var metaChips: some View {
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
    }
}

private extension JellyfinMediaItem {
    /// "T2 E5 · Nombre del episodio" for the hero eyebrow line.
    var episodeLabelAndName: String {
        if let label = episodeLabel {
            return "\(label) · \(name)"
        }
        return name
    }
}

/// Thin progress bar used by the hero card.
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

/// Coherent placeholder when the library has no hero-worthy content yet.
struct HeroEmptyStateView: View {
    var body: some View {
        HStack(spacing: MareaTheme.Spacing.md) {
            Image(systemName: "film.stack")
                .font(.title)
                .foregroundStyle(.white.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text("Nada destacado todavía")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Tu biblioteca aparecerá aquí en cuanto haya contenido.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(MareaTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(MareaTheme.Colors.surface, in: RoundedRectangle(cornerRadius: MareaTheme.Radius.hero))
        .padding(.horizontal, MareaTheme.Spacing.md)
    }
}
