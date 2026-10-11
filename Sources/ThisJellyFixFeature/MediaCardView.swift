import SwiftUI
import ThisJellyFixCore

struct MediaCardView: View {
    let item: JellyfinMediaItem
    let imageURL: URL?
    /// Render the card in landscape 16:9 (resume row) instead of portrait poster.
    var wide: Bool = false
    /// Portrait poster tried when the wide frame can't be fetched.
    var fallbackImageURL: URL? = nil
    /// Overlay badge (bottom-left) — Netflix-style "Nueva temporada" / "Siguiente episodio".
    var badge: CardBadge? = nil
    @State private var isAppeared = false

    private var isEpisode: Bool { item.type == "Episode" }
    private var isWide: Bool { wide || isEpisode }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail
            MareaImageView(
                url: imageURL,
                placeholder: String(item.name.prefix(1)),
                width: cardWidth,
                height: cardHeight,
                fallbackURL: fallbackImageURL
            )
            .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
            .overlay(alignment: .bottom) {
                // Progress bar
                if let percentage = item.playedPercentage, percentage > 0 {
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(.black.opacity(0.6))
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(MareaTheme.Colors.accent)
                                        .frame(width: geo.size.width * percentage / 100.0)
                                        .animation(.easeInOut(duration: 0.5), value: percentage)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
                }

                // Play button overlay for wide cards with progress
                if isWide, item.playedPercentage != nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.5), in: Circle())
                        .opacity(isAppeared ? 1 : 0)
                }

                // Badge overlay (bottom-left, over the image)
                if let badge {
                    BadgeView(badge: badge)
                        .padding(MareaTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .overlay {
                // Subtle light border on landscape cards
                if isWide {
                    RoundedRectangle(cornerRadius: MareaTheme.Radius.card)
                        .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

            // Text below card
            if isEpisode {
                // Series name (bold, primary)
                if let seriesName = item.seriesName {
                    Text(seriesName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: cardWidth, alignment: .leading)
                }
                // Episode label + name
                HStack(spacing: 4) {
                    if let label = item.episodeLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(MareaTheme.Colors.accent)
                    }
                    Text(item.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: cardWidth, alignment: .leading)
            } else {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(width: cardWidth, alignment: .leading)

                if let year = item.year {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scaleEffect(isAppeared ? 1 : 0.9)
        .opacity(isAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double.random(in: 0...0.15))) {
                isAppeared = true
            }
        }
    }

    private var cardWidth: CGFloat {
        #if os(macOS)
        // Desktop wrap grid: posters read at arm's length, so they scale up
        // from the phone size instead of staying phone-small in a big window.
        isWide ? 320 : 170
        #else
        isWide ? 240 : 150
        #endif
    }

    private var cardHeight: CGFloat {
        #if os(macOS)
        isWide ? 180 : 255  // 16:9 for episodes/resume, 2:3 poster otherwise
        #else
        isWide ? 135 : 220  // 16:9 for episodes/resume, portrait for movies/series
        #endif
    }
}
