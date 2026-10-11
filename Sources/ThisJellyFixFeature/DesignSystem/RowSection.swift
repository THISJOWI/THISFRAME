import SwiftUI
import ThisJellyFixCore

/// Horizontal content row with a title, optional "Ver todo" link and
/// peek-style scrolling (the next card peeks in from the trailing edge).
struct RowSection: View {
    let title: String
    let items: [JellyfinMediaItem]
    /// Landscape 16:9 cards (resume row) instead of portrait posters.
    var wide: Bool = false
    /// Badge overlay per card (nil = no badge).
    var badgeFor: ((JellyfinMediaItem) -> CardBadge?)? = nil
    /// Builds the poster URL for a card.
    var imageURL: (JellyfinMediaItem) -> URL?
    /// Fallback poster for wide cards whose Thumb/Backdrop frame is missing.
    var fallbackImageURL: ((JellyfinMediaItem) -> URL?)? = nil
    /// Direct playback (episodes/movies) bypasses DetailView.
    var onPlayDirect: ((JellyfinMediaItem) -> Void)? = nil
    /// "Ver todo" handler — nil hides the link (tvOS/visionOS).
    var onSeeAll: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: MareaTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 2) {
                            Text("Ver todo")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MareaTheme.Spacing.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                // viewAligned gives Netflix-style peek: cards snap to the
                // leading edge and the next one stays visible at the trailing.
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        card(for: item)
                    }
                }
                .padding(.horizontal, MareaTheme.Spacing.xl)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.05)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private func card(for item: JellyfinMediaItem) -> some View {
        let card = cardView(for: item)

        if item.type == "Episode" || item.type == "Movie", let onPlayDirect {
            // Direct playback — no DetailView in between.
            Button { onPlayDirect(item) } label: { card }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) { card }
                .buttonStyle(.plain)
        }
    }

    private func cardView(for item: JellyfinMediaItem) -> AnyView {
        if wide {
            // "Estás viendo": dedicated panoramic card — 16:9 backdrop with
            // title on the scrim and a progress bar on the lower edge.
            return AnyView(ResumeCardView(
                item: item,
                imageURL: imageURL(item),
                fallbackImageURL: fallbackImageURL?(item)
            ))
        }
        return AnyView(MediaCardView(
            item: item,
            imageURL: imageURL(item),
            wide: wide,
            fallbackImageURL: fallbackImageURL?(item),
            badge: badgeFor?(item)
        ))
    }
}
