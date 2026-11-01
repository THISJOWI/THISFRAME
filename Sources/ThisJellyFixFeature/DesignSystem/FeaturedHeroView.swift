import SwiftUI
import ThisJellyFixCore

/// A series plus the episode the viewer would resume, if any.
///
/// Home feeds this from the real Jellyfin rows: the series itself comes from
/// the Series / recently-added shelves, the episode from "Estás viendo".
struct FeaturedSeries: Identifiable {
    let series: JellyfinMediaItem
    let resumeEpisode: JellyfinMediaItem?

    var id: String { series.id }
}

/// Cinematic banner at the top of Home, dedicated to recommended series.
///
/// The brand header (icon, wordmark, action pill) is part of the same
/// composition: it sits on the artwork behind a top scrim instead of in a
/// separate bar above it. Artwork, copy and actions all come from Jellyfin.
struct FeaturedHeroView<Header: View>: View {
    let items: [FeaturedSeries]
    let serverURL: URL
    /// Plays the in-progress episode, or opens the series when there is none.
    let onPrimaryAction: (FeaturedSeries) -> Void
    /// Opens the series detail screen.
    let onMoreInfo: (FeaturedSeries) -> Void
    /// Brand header rendered inside the hero (logo, wordmark, action pill).
    @ViewBuilder let header: () -> Header

    @State private var selectedID: JellyfinMediaItem.ID?

    var body: some View {
        if !items.isEmpty {
            ZStack(alignment: .top) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(items) { item in
                            FeaturedHeroCard(
                                item: item,
                                imageURL: heroImageURL(for: item),
                                posterURL: item.series.artworkURL(serverURL: serverURL, shape: .poster),
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

                // Top scrim: keeps the integrated brand header legible on any
                // artwork, in both appearances.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.62), location: 0),
                        .init(color: .black.opacity(0.22), location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 150)
                .allowsHitTesting(false)

                header()
                    .padding(.horizontal, MareaTheme.Spacing.lg)
                    .padding(.top, MareaTheme.Spacing.sm)

                if items.count > 1 {
                    pageIndicator
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, MareaTheme.Spacing.lg)
                        .padding(.top, 64)
                }
            }
            .frame(height: heroHeight)
            .onAppear {
                if selectedID == nil { selectedID = items.first?.id }
            }
        }
    }

    private func heroImageURL(for item: FeaturedSeries) -> URL? {
        // The series backdrop is the cinematic shot; fall back to the resume
        // episode's backdrop and finally to the poster.
        if let url = JellyfinArtwork.url(
            for: item.series,
            serverURL: serverURL,
            shape: .landscape,
            targetWidth: 900
        ) {
            return url
        }
        if let episode = item.resumeEpisode,
           let url = JellyfinArtwork.url(
               for: episode,
               serverURL: serverURL,
               shape: .landscape,
               targetWidth: 900
           ) {
            return url
        }
        return item.series.artworkURL(serverURL: serverURL, shape: .poster)
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
        620
        #elseif os(macOS) || os(visionOS)
        540
        #else
        520
        #endif
    }
}

private struct FeaturedHeroCard: View {
    let item: FeaturedSeries
    let imageURL: URL?
    let posterURL: URL?
    let onPrimaryAction: () -> Void
    let onMoreInfo: () -> Void

    private var series: JellyfinMediaItem { item.series }

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

            // Heavier at the bottom: title, metadata and actions stay legible
            // on any artwork and melt into the page background.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.02), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.42),
                    .init(color: .black.opacity(0.74), location: 0.78),
                    .init(color: MareaTheme.Colors.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(2)
                }

                Text(displayTitle)
                    .font(.system(size: titleSize, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 3)

                Text(metadataLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)

                if let overview = series.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 620, alignment: .leading)
                }

                actions
                    .padding(.top, 4)
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
                HStack(spacing: 9) {
                    Image(systemName: primaryIcon)
                        .font(.system(size: 15, weight: .bold))
                    Text(primaryLabel)
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(MareaTheme.Colors.accent, in: Capsule())
                .shadow(color: MareaTheme.Colors.accent.opacity(0.35), radius: 10, y: 4)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onMoreInfo) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Más información")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(.black.opacity(0.28), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var displayTitle: String {
        series.name
    }

    private var eyebrow: String? {
        if let episode = item.resumeEpisode {
            return "\(episode.episodeLabel) · \(episode.name)"
        }
        if let genres = series.genres, !genres.isEmpty {
            return genres.prefix(2).joined(separator: " · ")
        }
        return "Serie recomendada"
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let year = series.year { parts.append(String(year)) }
        if let rating = series.officialRating, !rating.isEmpty { parts.append(rating) }
        if let genres = series.genres, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        if parts.isEmpty { parts.append("Serie") }
        return parts.joined(separator: " · ")
    }

    private var primaryLabel: String {
        item.resumeEpisode != nil ? "Continuar" : "Ver episodios"
    }

    private var primaryIcon: String {
        item.resumeEpisode != nil ? "play.fill" : "list.bullet"
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
