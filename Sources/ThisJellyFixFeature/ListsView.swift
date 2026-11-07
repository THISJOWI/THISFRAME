import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Browse the user's playlists and server collections.
///
/// Playlists are user-created lists; collections (BoxSets) come from the
/// server. Each entry opens its detail screen where items can be added,
/// removed, reordered or the list renamed/deleted.
struct ListsView: View {
    let serverURL: URL
    let token: String
    let userId: String

    @State private var playlists: [JellyfinMediaItem] = []
    @State private var collections: [JellyfinMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingCreate = false

    private let client: any JellyfinPlaylistProviding

    init(
        serverURL: URL,
        token: String,
        userId: String,
        client: any JellyfinPlaylistProviding = JellyfinPlaylistClient()
    ) {
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView("Cargando listas…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Reintentar") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    if !playlists.isEmpty {
                        section(title: "Tus listas", items: playlists, kind: .playlist)
                    }

                    if !collections.isEmpty {
                        section(title: "Colecciones del servidor", items: collections, kind: .collection)
                    }

                    if playlists.isEmpty && collections.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 48))
                                .foregroundStyle(MareaTheme.Colors.accent.opacity(0.6))
                            Text("No hay listas aún")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Crea tu primera lista para organizar tus películas y series favoritas")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(MareaTheme.Colors.background)
        .navigationTitle("Listas")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Crear lista")
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateListView(
                serverURL: serverURL,
                token: token,
                userId: userId,
                onCreated: { Task { await load() } }
            )
        }
        .task { await load() }
        .refreshable { await load() }
        // Single destination for this host stack. Playlists and collections
        // open ListDetailView; any media item inside them opens DetailView.
        // (Declaring a second `navigationDestination(for: JellyfinMediaItem.self)`
        // in ListDetailView left two registrations for one type in the same
        // stack — ambiguous at push time and a crash source, so the dispatch
        // happens HERE, by item type.)
        .navigationDestination(for: JellyfinMediaItem.self) { item in
            destinationView(for: item)
        }
    }

    /// Type-based dispatch for the stack's single media destination.
    @ViewBuilder
    private func destinationView(for item: JellyfinMediaItem) -> some View {
        let kind = item.type.lowercased()
        if kind == "playlist" || kind == "boxset" || kind == "collectionfolder" {
            ListDetailView(
                playlist: item,
                serverURL: serverURL,
                token: token,
                userId: userId
            )
        } else {
            DetailView(
                item: item,
                serverURL: serverURL,
                token: token,
                userId: userId,
                onPlayerDismiss: {}
            )
        }
    }

    @ViewBuilder
    private func section(title: String, items: [JellyfinMediaItem], kind: ListKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                        NavigationLink(value: item) {
                            ListItemCard(
                                item: item,
                                kind: kind,
                                imageURL: item.artworkURL(serverURL: serverURL)
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let playlistsTask = client.fetchPlaylists(
                userId: userId, serverURL: serverURL, token: token
            )
            async let collectionsTask = client.fetchCollections(
                userId: userId, serverURL: serverURL, token: token
            )

            let (fetchedPlaylists, fetchedCollections) = try await (playlistsTask, collectionsTask)
            playlists = fetchedPlaylists
            collections = fetchedCollections
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Playlist vs server collection — determines which actions are available.
private enum ListKind { case playlist, collection }

/// Card for a playlist or collection entry.
private struct ListItemCard: View {
    let item: JellyfinMediaItem
    let kind: ListKind
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MareaImageView(
                url: imageURL,
                placeholder: String(item.name.prefix(1)),
                width: 150,
                height: 220
            )
            .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))

            if let count = item.childCount, count > 0 {
                Text("\(count) \(count == 1 ? "elemento" : "elementos")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if kind == .playlist {
                Label("Lista personal", systemImage: "person.crop.circle")
                    .font(.caption2)
                    .foregroundStyle(MareaTheme.Colors.accentText)
            } else {
                Label("Colección del servidor", systemImage: "building.2")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 150)
    }
}
