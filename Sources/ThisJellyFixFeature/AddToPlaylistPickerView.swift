import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Lets the user pick (or create) a playlist to add the current item to.
struct AddToPlaylistPickerView: View {
    let itemId: String
    let serverURL: URL
    let token: String
    let userId: String

    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [JellyfinMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAdding = false
    @State private var addedTo: String?

    private let client: any JellyfinPlaylistProviding = JellyfinPlaylistClient()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Cargando listas…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage).foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    VStack(spacing: 12) {
                        Text("No hay listas aún")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Crea una lista primero desde la pestaña Listas.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            Button {
                                Task { await add(to: playlist) }
                            } label: {
                                HStack {
                                    Text(playlist.name)
                                    Spacer()
                                    if isAdding {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isAdding)
                        }
                    }
                }
            }
            .navigationTitle("Añadir a lista")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .overlay {
                if let addedTo {
                    VStack {
                        Spacer()
                        Text("Añadido a «\(addedTo)»")
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding()
                    }
                    .transition(.opacity)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            playlists = try await client.fetchPlaylists(
                userId: userId, serverURL: serverURL, token: token
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(to playlist: JellyfinMediaItem) async {
        isAdding = true
        defer { isAdding = false }
        do {
            try await client.addItems(
                playlistId: playlist.id,
                itemIds: [itemId],
                userId: userId,
                serverURL: serverURL,
                token: token
            )
            addedTo = playlist.name
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}