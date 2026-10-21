import SwiftUI
import ThisJellyFixCore

/// A card for a library item.
///
/// The card's width follows its container: rows that scroll horizontally
/// keep the designed size, grids let the card fill the column it was given.
/// That is what keeps an episode cover from spilling out of its cell and
/// over the next one.
struct MediaCardView: View {
    let item: JellyfinMediaItem
    let imageURL: URL?
    /// Render the card in landscape 16:9 (resume row) instead of portrait poster.
    var wide: Bool = false
    /// Fill the width the container offers instead of using the designed card
    /// size. Grids need this: a fixed width overflows the column.
    var flexibleWidth: Bool = false
    /// Portrait poster tried when the wide frame can't be fetched.
    var fallbackImageURL: URL? = nil
    /// Overlay badge (bottom-left) — Netflix-style "Nueva temporada" / "Siguiente episodio".
    var badge: CardBadge? = nil
    /// Position in the row — drives the entrance stagger.
    var appearIndex: Int = 0
    /// False for cards that must appear already in place (the row revealed
    /// them later, while the user was scrolling).
    var revealWithRow: Bool = true

    private var isEpisode: Bool { item.type == "Episode" }
    private var isWide: Bool { wide || isEpisode }
    /// Episodes are 16:9 frames, everything else a 2:3 poster.
    private var shape: MediaCardLayout.Shape { isWide ? .landscape : .poster }

    /// The designed card width, used by the rows that scroll horizontally.
    private var designedWidth: CGFloat {
        #if os(macOS)
        // Desktop wrap grid: posters read at arm's length, so they scale up
        // from the phone size instead of staying phone-small in a big window.
        isWide ? 320 : 170
        #else
        isWide ? 240 : 150
        #endif
    }

    /// Height of the designed card, derived from the shape so the artwork
    /// box is always the right ratio.
    private var designedHeight: CGFloat {
        MediaCardLayout.height(forWidth: designedWidth, shape: shape)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail
            thumbnail
            // Text below card
            labels
        }
        .cardEntrance(index: appearIndex, animates: revealWithRow)
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        MareaImageView(
            url: imageURL,
            placeholder: String(item.name.prefix(1)),
            width: flexibleWidth ? 0 : designedWidth,
            height: flexibleWidth ? 0 : designedHeight,
            aspectRatio: flexibleWidth ? shape.aspectRatio : nil,
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
    }

    // MARK: - Labels

    @ViewBuilder
    private var labels: some View {
        if isEpisode {
            // Series name (bold, primary)
            if let seriesName = item.seriesName {
                cardWidth {
                    Text(seriesName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            // Episode label + name
            cardWidth {
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
            }
        } else {
            cardWidth {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(2)
            }

            if let year = item.year {
                cardWidth {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Pins the label to the card's width. In a grid the card fills its
    /// column, so the label follows the column instead of a fixed size.
    @ViewBuilder
    private func cardWidth<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if flexibleWidth {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
                .frame(width: designedWidth, alignment: .leading)
        }
    }
}
