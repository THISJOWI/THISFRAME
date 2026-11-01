import SwiftUI
import ThisJellyFixCore

/// Cinematic featured banner used at the top of Home.
///
/// The artwork is real Jellyfin content: the same item the row below can play
/// or open. It deliberately reuses the app's existing accent, typography and
/// image renderer instead of introducing a second visual language.
struct FeaturedHeroView: View {
    let items: [JellyfinMediaItem]
    let serverURL: URL
    /// Direct playback for movies/episodes, or the detail screen for series.
    let onPrimaryAction: (JellyfinMediaItem) -> Void
    /// Opens the title's detail screen when the primary action is playback.
    let onMoreInfo: (JellyfinMediaItem) -> Void

    @State private var selectedID: JellyfinMediaItem.ID?

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        FeaturedHeroCard(
                            item: item,
                            imageURL: heroImageURL(for: item),
                            posterURL: item.artworkURL(serverURL: serverURL, shape: .poster),
                            onPrimaryAction: { onPrimaryAction(item) },
                            onMoreInfo: { onMoreInfo(item) }
                        )
                        .containerRelativeFrame(.horizontal)
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedID)
            .frame(height: heroHeight)
            .overlay(alignment: .topTrailing) {
                if items.count > 1 {
                    pageIndicator
                        .padding(MareaTheme.Spacing.md)
                }
            }
            .onAppear {
                if selectedID == nil { selectedID = items.first?.id }
            }
        }
    }

    private func heroImageURL(for item: JellyfinMediaItem) -> URL? {
        JellyfinArtwork.url(
            for: item,
            serverURL: serverURL,
            shape: .landscape,
            targetWidth: 900
        )
    }

    private var pageIndicator: some View {
        HStack(spacing: 5) {
            ForEach(items) { item in
                Capsule()
                    .fill(item.id == selectedID ? Color.white : Color.white.opacity(0.35))
                    .frame(width: item.id == selectedID ? 18 : 6, height: 6)
                    .animation(MareaMotion.quick, value: selectedID)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
    }

    private var heroHeight: CGFloat {
        #if os(tvOS)
        560
        #elseif os(macOS) || os(visionOS)
        500
        #else
        460
        #endif
    }
}

private struct FeaturedHeroCard: View {
    let item: JellyfinMediaItem
    let imageURL: URL?
    let posterURL: URL?
    let onPrimaryAction: () -> Void
    let onMoreInfo: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MareaImageView(
                url: imageURL,
                placeholder: String(displayTitle.prefix(1)),
                width: 0,
                height: 0,
                fallbackURL: posterURL
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // The scrim is intentionally heavier at the bottom: title,
            // metadata and actions stay legible on any artwork, in both modes.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.05), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.38),
                    .init(color: .black.opacity(0.78), location: 0.78),
                    .init(color: MareaTheme.Colors.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Text(displayTitle)
                    .font(.system(size: titleSize, weight: .heavy, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

                Text(metadataLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 620, alignment: .leading)
                }

                actions
                    .padding(.top, 2)
            }
            .padding(.horizontal, MareaTheme.Spacing.lg)
            .padding(.bottom, MareaTheme.Spacing.lg)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        HStack(spacing: MareaTheme.Spacing.sm) {
            Button(action: onPrimaryAction) {
                Label(primaryLabel, systemImage: primaryIcon)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(MareaTheme.Colors.accent)
            .foregroundStyle(.white)

            if item.type != "Series" {
                Button(action: onMoreInfo) {
                    Label("Más información", systemImage: "info.circle")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.black.opacity(0.3), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var displayTitle: String {
        item.type == "Episode" ? (item.seriesName ?? item.name) : item.name
    }

    private var eyebrow: String? {
        if item.type == "Episode" {
            return item.episodeDisplayTitle
        }
        return item.type == "Movie" ? "Película destacada" : "Serie destacada"
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if let rating = item.officialRating, !rating.isEmpty { parts.append(rating) }
        if let genres = item.genres, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        if parts.isEmpty {
            parts.append(item.type == "Movie" ? "Película" : "Serie")
        }
        return parts.joined(separator: " · ")
    }

    private var primaryLabel: String {
        if item.type == "Series" { return "Ver episodios" }
        return item.resumePositionSeconds != nil ? "Continuar" : "Reproducir"
    }

    private var primaryIcon: String {
        item.type == "Series" ? "list.bullet" : "play.fill"
    }

    private var titleSize: CGFloat {
        #if os(tvOS)
        58
        #elseif os(macOS) || os(visionOS)
        48
        #else
        36
        #endif
    }
}
