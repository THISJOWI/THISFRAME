import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Detail of a playlist or collection: its items, plus add / remove / edit.
///
/// Playlists can be renamed, have items added or removed, and be deleted.
/// Server collections are read-only: only their items are shown.
struct ListDetailView: View {
    let playlist: JellyfinMediaItem
    let serverURL: URL
    let token: String
    let userId: String

    @Environment(\.dismiss) private var dismiss

    @State private var items: [JellyfinMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingEdit = false
    @State private var showingAdd = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false

    private let client: any JellyfinPlaylistProviding

    /// Whether this is a user playlist (editable) or a server collection (read-only).
    private var isPlaylist: Bool { playlist.type.lowercased() == "playlist" }

    init(
        playlist: JellyfinMediaItem,
        serverURL: URL,
        token: String,
        userId: String,
        client: any JellyfinPlaylistProviding = JellyfinPlaylistClient()
    ) {
        self.playlist = playlist
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with cover + actions
                header

                if isLoading {
                    ProgressView("Cargando elementos…")
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
                        Button("Reintentar") { Task { await loadItems() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.circle")
                            .font(.system(size: 56))
                            .foregroundStyle(MareaTheme.Colors.accent.opacity(0.6))
                        Text("Lista vacía")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if isPlaylist {
                            Text("Añade películas y series para comenzar a organizar tu lista.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    // Items grid
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(items.count) \(items.count == 1 ? "elemento" : "elementos")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 180), spacing: MareaTheme.Spacing.md)
                            ],
                            spacing: MareaTheme.Spacing.md
                        ) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                VStack(spacing: 6) {
                                    NavigationLink(value: item) {
                                        MediaCardView(
                                            item: item,
                                            imageURL: item.artworkURL(serverURL: serverURL),
                                            flexibleWidth: true,
                                            revealWithRow: false
                                        )
                                    }
                                    .buttonStyle(PressableCardStyle())

                                    if isPlaylist {
                                        Button {
                                            Task { await removeItem(at: index) }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Eliminar de la lista")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(MareaTheme.Colors.background)
        .navigationTitle(playlist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isPlaylist {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Eliminar lista")

                    Button {
                        showingEdit = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Editar lista")

                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Añadir elementos")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditListView(
                playlist: playlist,
                serverURL: serverURL,
                token: token,
                onSaved: { Task { await load() } }
            )
        }
        .sheet(isPresented: $showingAdd) {
            AddToListView(
                playlistId: playlist.id ?? "",
                serverURL: serverURL,
                token: token,
                userId: userId,
                onAdded: { Task { await loadItems() } }
            )
        }
        .confirmationDialog(
            "¿Eliminar «\(playlist.name)»?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                Task { await deletePlaylist() }
            }
        } message: {
            Text("Esta acción no se puede deshacer. Los elementos de la lista no se borrarán de tu biblioteca.")
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(for: JellyfinMediaItem.self) { item in
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
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            if let url = playlist.artworkURL(serverURL: serverURL, shape: .poster) {
                MareaImageView(
                    url: url,
                    placeholder: String(playlist.name.prefix(1)),
                    width: 80,
                    height: 120
                )
                .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
            } else {
                RoundedRectangle(cornerRadius: MareaTheme.Radius.card)
                    .fill(MareaTheme.Colors.overlayFill.opacity(0.3))
                    .frame(width: 80, height: 120)
                    .overlay(
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.title2.bold())
                    .lineLimit(2)

                if let overview = playlist.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Label {
                    Text(playlist.type.lowercased() == "playlist" ? "Lista personal" : "Colección del servidor")
                        .font(.caption)
                } icon: {
                    Image(systemName: playlist.type.lowercased() == "playlist" ? "person.crop.circle" : "building.2")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let itemsTask = client.fetchPlaylistItems(
                playlistId: playlist.id ?? "",
                userId: userId,
                serverURL: serverURL,
                token: token
            )
            items = try await itemsTask
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadItems() async {
        do {
            items = try await client.fetchPlaylistItems(
                playlistId: playlist.id ?? "",
                userId: userId,
                serverURL: serverURL,
                token: token
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeItem(at index: Int) async {
        guard index < items.count else { return }
        let item = items[index]
        guard let entryId = item.playlistItemId else { return }

        do {
            try await client.removeItems(
                playlistId: playlist.id ?? "",
                entryIds: [entryId],
                serverURL: serverURL,
                token: token
            )
            items.remove(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePlaylist() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await client.deletePlaylist(
                playlistId: playlist.id ?? "",
                serverURL: serverURL,
                token: token
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
