import SwiftUI
import ThisJellyFixCore
import ThisJellyFixNetworking

/// Create a new playlist: name, optional description.
///
/// After creation the user lands in ListDetailView where they can add items.
struct CreateListView: View {
    let serverURL: URL
    let token: String
    let userId: String
    var onCreated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let client: any JellyfinPlaylistProviding

    init(
        serverURL: URL,
        token: String,
        userId: String,
        client: any JellyfinPlaylistProviding = JellyfinPlaylistClient(),
        onCreated: (() -> Void)? = nil
    ) {
        self.serverURL = serverURL
        self.token = token
        self.userId = userId
        self.client = client
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Nombre de la lista", text: $name)
                }

                Section("Descripción (opcional)") {
                    TextField("¿Qué contiene esta lista?", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Nueva lista")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .overlay {
                if isCreating {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView("Creando…")
                    }
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let id = try await client.createPlaylist(
                name: trimmed,
                description: description.isEmpty ? nil : description,
                itemIds: [],
                userId: userId,
                serverURL: serverURL,
                token: token
            )
            _ = id
            onCreated?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Edit a playlist's name and description.
struct EditListView: View {
    let playlist: JellyfinMediaItem
    let serverURL: URL
    let token: String
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let client: any JellyfinPlaylistProviding

    init(
        playlist: JellyfinMediaItem,
        serverURL: URL,
        token: String,
        client: any JellyfinPlaylistProviding = JellyfinPlaylistClient(),
        onSaved: (() -> Void)? = nil
    ) {
        self.playlist = playlist
        self.serverURL = serverURL
        self.token = token
        self.client = client
        self.onSaved = onSaved
        _name = State(initialValue: playlist.name)
        _description = State(initialValue: playlist.overview ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Nombre de la lista", text: $name)
                }

                Section("Descripción") {
                    TextField("Descripción", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Editar lista")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView("Guardando…")
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await client.updatePlaylist(
                playlistId: playlist.id ?? "",
                name: trimmed,
                description: description.isEmpty ? nil : description,
                serverURL: serverURL,
                token: token
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
