import SwiftUI
import ThisJellyFixCore
#if canImport(UIKit)
import UIKit
#endif

/// Panoramic 16:9 card for the "Estás viendo" row — backdrop with the title
/// and episode info layered on a bottom scrim, a thin progress bar pinned to
/// the card's lower edge and a play overlay. Responsive: the width scales
/// with the available space instead of a fixed 240pt.
struct ResumeCardView: View {
    let item: JellyfinMediaItem
    /// Landscape backdrop (Thumb/Backdrop frame).
    let imageURL: URL?
    /// Portrait poster tried when no 16:9 frame exists.
    var fallbackImageURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MareaTheme.Spacing.xs) {
            artwork
                .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: MareaTheme.Radius.card)
                        .strokeBorder(MareaTheme.Colors.borderGlow, lineWidth: 1)
                }
                .overlay(alignment: .center) {
                    playOverlay
                }
                .overlay(alignment: .bottom) {
                    if let percentage = item.playedPercentage, percentage > 0 {
                        progressBar(percentage)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            // Context line below the card: episode label + remaining time.
            if let context = contextLabel {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth)
    }

    // MARK: - Pieces

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            MareaImageView(
                url: imageURL,
                placeholder: String(item.name.prefix(1)),
                width: 0,
                height: 0,
                fallbackURL: fallbackImageURL
            )
            .frame(maxWidth: .infinity)
            .frame(height: artworkHeight)
            .clipped()

            // Title + series on the scrim so the card reads without
            // leaving the row.
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                if let series = item.seriesName {
                    Text(series)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text(item.type == "Episode" ? item.name : item.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(MareaTheme.Spacing.sm)
            .padding(.bottom, 4)
        }
    }

    private var playOverlay: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.5), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(radius: 4)
            .opacity(item.playedPercentage != nil ? 1 : 0.9)
    }

    private func progressBar(_ percentage: Double) -> some View {
        // The bar sits on the card's dark scrim: the channel must be LIGHT
        // in both modes, or it disappears into the artwork.
        ProgressBarView(
            fraction: percentage / 100.0,
            height: 4,
            track: Color.white.opacity(0.25)
        )
    }

    /// "T1 E3 · Vas por 12 min" — what the viewer needs at a glance. The row
    /// DTO carries no runtime, so only the position can be stated honestly.
    private var contextLabel: String? {
        var parts: [String] = []
        if let label = item.episodeLabel {
            parts.append(label)
        }
        if let position = item.positionMinutes {
            parts.append("Vas por \(position) min")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Metrics

    /// Responsive: track the available width (capped) instead of a fixed
    /// card size, so the row adapts to iPhone SE → iPad → Mac windows.
    private var cardWidth: CGFloat {
        #if os(iOS) || os(tvOS)
        min(max(UIScreen.main.bounds.width * 0.72, 240), 360)
        #else
        300
        #endif
    }

    private var artworkHeight: CGFloat {
        cardWidth * 9 / 16
    }
}

private extension JellyfinMediaItem {
    /// Minutes already watched (position ticks → minutes). nil = never started.
    var positionMinutes: Int? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return max(1, Int((Double(ticks) / 10_000_000 / 60).rounded()))
    }
}
