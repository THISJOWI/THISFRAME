import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Pick library items to add to a playlist.
///
/// Shows movies and series from the user's library with checkmarks for
/// selection. Selected items are appended to the playlist on save.
struct AddToListView: View {
    let playlistId: String
    let serverURL: URL
    let token: String
    let userId: String
    var onAdded: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var items: [JellyfinMediaItem] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAdding = false

    private let libraryClient: any JellyfinLibraryProviding
    private let playlistClient: any JellyfinPlaylistProviding

    init(
        playlistId: String,
        serverURL: URL,
        token: String,
        userId: String,
        libraryClient: any JellyfinLibraryProviding = JellyfinLibraryClient(),
        playlistClient: any JellyfinPlaylistProviding = JellyfinPlaylistClient(),
        onAdded: (() -> Void)? = nil
    ) {
        self.playlistId = playlistId
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.libraryClient = libraryClient
        self.playlistClient = playlistClient
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        ProgressView("Buscando contenido…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    } else if let errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                            Button("Reintentar") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        Text("Selecciona las películas y series que quieres añadir a la lista")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 120, maximum: 180), spacing: MareaTheme.Spacing.md)
                            ],
                            spacing: MareaTheme.Spacing.md
                        ) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                                Button {
                                    toggle(item)
                                } label: {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            MediaCardView(
                                                item: item,
                                                imageURL: item.artworkURL(serverURL: serverURL),
                                                flexibleWidth: true,
                                                revealWithRow: false
                                            )
                                            .opacity(selectedIDs.contains(item.id) ? 0.85 : 1)

                                            if selectedIDs.contains(item.id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(MareaTheme.Colors.accent)
                                                    .background(.white.opacity(0.9), in: Circle())
                                                    .offset(x: 14, y: -14)
                                            }
                                        }

                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if items.isEmpty {
                            ContentUnavailableView(
                                "Sin contenido",
                                systemImage: "film.stack",
                                description: Text("No se encontraron películas o series en la biblioteca.")
                            )
                            .padding(.top, 60)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(MareaTheme.Colors.background)
            .navigationTitle("Añadir elementos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir \(selectedIDs.count)") { Task { await addSelected() } }
                        .disabled(selectedIDs.isEmpty || isAdding)
                }
            }
            .overlay {
                if isAdding {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView("Añadiendo…")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func toggle(_ item: JellyfinMediaItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch movies and series in parallel.
            async let moviesTask = libraryClient.fetchItems(
                userId: userId, serverURL: serverURL, token: token,
                parentId: nil, includeTypes: "Movie",
                limit: 100, orderBy: "SortName", filters: nil
            )
            async let seriesTask = libraryClient.fetchItems(
                userId: userId, serverURL: serverURL, token: token,
                parentId: nil, includeTypes: "Series",
                limit: 100, orderBy: "SortName", filters: nil
            )

            let (movies, series) = try await (moviesTask, seriesTask)
            items = Array(Set(movies + series))
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSelected() async {
        isAdding = true
        defer { isAdding = false }

        let ids = Array(selectedIDs)
        do {
            try await playlistClient.addItems(
                playlistId: playlistId,
                itemIds: ids,
                userId: userId,
                serverURL: serverURL,
                token: token
            )
            onAdded?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
