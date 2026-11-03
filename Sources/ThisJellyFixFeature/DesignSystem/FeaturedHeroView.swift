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
            ZStack(alignment: .bottom) {
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

                // Top scrim: keeps the integrated brand header and system status bar
                // legible on any artwork. Extends into the status bar on iOS edge-to-edge.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .allowsHitTesting(false)
                .ignoresSafeArea(.container, edges: .top)
                .frame(maxHeight: .infinity, alignment: .top)

                header()
                    .padding(.horizontal, MareaTheme.Spacing.lg)
                    .padding(.top, headerTopPadding)
                    .frame(maxHeight: .infinity, alignment: .top)

                if items.count > 1 {
                    pageIndicator
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 32)
                }
            }
            .frame(height: heroHeight)
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                if selectedID == nil { selectedID = items.first?.id }
            }
        }
    }

    /// Top padding for the brand header so it clears the iOS status bar
    /// while the artwork stays edge-to-edge behind it.
    private var headerTopPadding: CGFloat {
        #if os(iOS)
        54
        #else
        MareaTheme.Spacing.sm
        #endif
    }

    private func heroImageURL(for item: FeaturedSeries) -> URL? {
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
        520
        #elseif os(macOS) || os(visionOS)
        440
        #else
        440
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

            // Heavier at the bottom: title and actions stay legible
            // on any artwork and melt into the page background.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.02), location: 0),
                    .init(color: .black.opacity(0.20), location: 0.45),
                    .init(color: .black.opacity(0.78), location: 0.82),
                    .init(color: MareaTheme.Colors.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(displayTitle)
                    .font(.system(size: titleSize, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                actions
                    .padding(.top, 2)
            }
            .padding(.horizontal, MareaTheme.Spacing.lg)
            .padding(.bottom, MareaTheme.Spacing.lg)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    /// Side by side when the width allows it, stacked on narrow phones so the
    /// labels never truncate or push past the safe area.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MareaTheme.Spacing.sm) {
                primaryActionButton
                moreInfoButton
            }
            VStack(alignment: .leading, spacing: MareaTheme.Spacing.sm) {
                primaryActionButton
                moreInfoButton
            }
        }
    }

    private var primaryActionButton: some View {
        Button(action: onPrimaryAction) {
            HStack(spacing: 7) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 13, weight: .bold))
                Text(primaryLabel)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(MareaTheme.Colors.accent, in: Capsule())
            .shadow(color: MareaTheme.Colors.accent.opacity(0.35), radius: 8, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var moreInfoButton: some View {
        Button(action: onMoreInfo) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("Más información")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.32), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        series.name
    }

    private var primaryLabel: String {
        item.resumeEpisode != nil ? "Continuar" : "Ver episodios"
    }

    private var primaryIcon: String {
        item.resumeEpisode != nil ? "play.fill" : "list.bullet"
    }

    private var titleSize: CGFloat {
        #if os(tvOS)
        44
        #elseif os(macOS) || os(visionOS)
        34
        #else
        22
        #endif
    }
}
