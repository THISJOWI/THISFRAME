import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

struct FavoritesView: View {
    let serverURL: URL
    let token: String
    let userId: String
    /// Embedded in Profile & Settings: no NavigationStack/ScrollView of its
    /// own, so the host screen owns scrolling and navigation.
    var embedded: Bool = false

    @State private var favoriteMovies: [JellyfinMediaItem] = []
    @State private var favoriteSeries: [JellyfinMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let libraryClient: any JellyfinLibraryProviding

    init(
        serverURL: URL,
        token: String,
        userId: String,
        embedded: Bool = false,
        libraryClient: any JellyfinLibraryProviding = JellyfinLibraryClient()
    ) {
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.embedded = embedded
        self.libraryClient = libraryClient
    }

    var body: some View {
        if embedded {
            content
                .navigationDestination(for: JellyfinMediaItem.self) { item in
                    DetailView(
                        item: item,
                        serverURL: serverURL,
                        token: token,
                        userId: userId
                    )
                }
                .task { await loadFavorites() }
        } else {
            NavigationStack {
                ScrollView {
                    content
                }
                .background(MareaTheme.Colors.surfaceOverlay)
                .refreshable { await loadFavorites() }
                .navigationTitle("Favoritos")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationDestination(for: JellyfinMediaItem.self) { item in
                    DetailView(
                        item: item,
                        serverURL: serverURL,
                        token: token,
                        userId: userId
                    )
                }
                .task { await loadFavorites() }
            }
        }
    }

    private var content: some View {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        ProgressView("Cargando favoritos…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if let errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Reintentar") { Task { await loadFavorites() } }
                                .buttonStyle(.bordered)
                            if !favoriteSeries.isEmpty {
                                favoritesSection(title: "Series", items: favoriteSeries)
                            }
                            if !favoriteMovies.isEmpty {
                                favoritesSection(title: "Películas", items: favoriteMovies)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else if favoriteMovies.isEmpty && favoriteSeries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "heart.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(MareaTheme.Colors.accent.opacity(0.6))
                            Text("Sin favoritos aún")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Marca contenido como favorito en Jellyfin")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        if !favoriteSeries.isEmpty {
                            favoritesSection(title: "Series", items: favoriteSeries)
                        }
                        if !favoriteMovies.isEmpty {
                            favoritesSection(title: "Películas", items: favoriteMovies)
                        }
                    }
                }
                .padding(.horizontal, embedded ? 0 : 24)
                .padding(.top, embedded ? 0 : 16)
    }

    private func favoritesSection(title: String, items: [JellyfinMediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                // Top-align so variable text height below posters doesn't
                // vertically offset them (default .center alignment).
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            MediaCardView(
                                item: item,
                                imageURL: imageURL(for: item),
                                // The cards come into view as the strip is
                                // scrolled: they show up already in place.
                                revealWithRow: false
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
        }
    }

    private func loadFavorites() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let moviesTask = libraryClient.fetchItems(
                userId: userId, serverURL: serverURL, token: token,
                parentId: nil, includeTypes: "Movie",
                limit: 30, orderBy: "DateCreated", filters: "IsFavorite"
            )
            async let seriesTask = libraryClient.fetchItems(
                userId: userId, serverURL: serverURL, token: token,
                parentId: nil, includeTypes: "Series",
                limit: 30, orderBy: "DateCreated", filters: "IsFavorite"
            )

            let (movies, series) = try await (moviesTask, seriesTask)
            // No global animation here: a `withAnimation` around the whole
            // assignment re-animates every card in the strip.
            favoriteMovies = movies
            favoriteSeries = series
            errorMessage = nil
        } catch {
            errorMessage = "No se pudieron cargar los favoritos. Comprueba la conexión e inténtalo de nuevo."
        }
    }

    private func imageURL(for item: JellyfinMediaItem) -> URL? {
        item.artworkURL(serverURL: serverURL)
    }
}
