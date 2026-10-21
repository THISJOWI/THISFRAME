#if os(iOS) || os(macOS)
import SwiftUI
import ThisJellyFixCore
import ThisJellyFixDiscovery

/// Horizontal shelf of catalogue items (Tendencias / Para ti). Cards push
/// `CatalogDetailView`, where the download action lives.
struct DiscoveryRowView: View {
    let row: CatalogRow
    let discovery: DiscoveryModel

    /// True once the shelf has been revealed — the cards that scroll in
    /// later are shown already in place.
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.title3.bold())
                if row.id == "forYou" {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(MareaTheme.Colors.accent)
                }
                Spacer()
            }
            .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            CatalogCardView(
                                item: item,
                                state: state(for: item),
                                appearIndex: index,
                                revealWithRow: !appeared
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(MareaMotion.gentle) { appeared = true }
        }
        .task {
            // First render: sync any orders already in flight elsewhere.
            if discovery.coordinator.entries.isEmpty {
                await discovery.refreshDownloads()
            }
        }
    }

    private func state(for item: CatalogItem) -> DownloadState? {
        discovery.coordinator.entries.first { entry in
            (item.tmdbId != nil && entry.tmdbId == item.tmdbId) || entry.title == item.title
        }?.state
    }
}
#endif
