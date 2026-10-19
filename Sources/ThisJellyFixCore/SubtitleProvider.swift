import Foundation

/// A subtitle source the app can search.
///
/// Two families live side by side:
/// - **Server providers** — the plugins the Jellyfin server runs. The app
///   asks the server and the server owns the credentials. The Jellyfin
///   OpenAPI exposes no way to install a provider, so the app can only use
///   the ones that are already there.
/// - **Client-side providers** — services the app queries itself with the
///   user's own credentials. The app downloads the file and hands it to the
///   server, which then behaves exactly as if the server had fetched it.
public enum SubtitleProviderID: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    /// The Jellyfin server's own subtitle providers (OpenSubtitles plugin…).
    case jellyfinServer
    /// OpenSubtitles.com, queried directly by the app.
    case openSubtitles

    public var id: String { rawValue }
}

/// Static description of a provider: what it is and what it needs from the
/// user before it can be used.
public struct SubtitleProviderDescriptor: Sendable, Equatable, Identifiable {
    public let id: SubtitleProviderID
    public let displayName: String
    /// One line explaining where the subtitles come from.
    public let summary: String
    /// True when the provider cannot be used until the user supplies a key.
    public let requiresAPIKey: Bool
    /// Where the user gets that key.
    public let apiKeyURL: URL?
    /// Where the provider is documented.
    public let documentationURL: URL?
    /// True when the app talks to the provider itself instead of asking the
    /// Jellyfin server to.
    public let isClientSide: Bool
    /// Built-in providers cannot be removed, only switched off.
    public let isRemovable: Bool

    public init(
        id: SubtitleProviderID,
        displayName: String,
        summary: String,
        requiresAPIKey: Bool,
        apiKeyURL: URL? = nil,
        documentationURL: URL? = nil,
        isClientSide: Bool,
        isRemovable: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.requiresAPIKey = requiresAPIKey
        self.apiKeyURL = apiKeyURL
        self.documentationURL = documentationURL
        self.isClientSide = isClientSide
        self.isRemovable = isRemovable
    }
}

/// The providers this build knows about. Adding a new one is a matter of
/// adding a case to `SubtitleProviderID` and a descriptor here — the store,
/// the settings UI and the player all work off the catalogue.
public enum SubtitleProviderCatalog {
    public static let all: [SubtitleProviderDescriptor] = [
        SubtitleProviderDescriptor(
            id: .jellyfinServer,
            displayName: "Jellyfin (servidor)",
            summary: "Usa los proveedores de subtítulos instalados en tu servidor Jellyfin. El servidor se encarga de buscarlos y de guardarlos junto al vídeo.",
            requiresAPIKey: false,
            apiKeyURL: nil,
            documentationURL: URL(string: "https://jellyfin.org/docs/general/server/plugins/"),
            isClientSide: false,
            isRemovable: false
        ),
        SubtitleProviderDescriptor(
            id: .openSubtitles,
            displayName: "OpenSubtitles.com",
            summary: "La app busca los subtítulos directamente en OpenSubtitles.com y los sube al servidor, así que el reproductor los carga como cualquier otro subtítulo externo.",
            requiresAPIKey: true,
            apiKeyURL: URL(string: "https://www.opensubtitles.com/en/consumers"),
            documentationURL: URL(string: "https://opensubtitles.stoplight.io/docs/opensubtitles-api"),
            isClientSide: true,
            isRemovable: true
        ),
    ]

    public static func descriptor(for id: SubtitleProviderID) -> SubtitleProviderDescriptor? {
        all.first { $0.id == id }
    }

    /// Providers the user can add from the settings screen.
    public static var addable: [SubtitleProviderDescriptor] {
        all.filter(\.isRemovable)
    }
}

/// The user's settings for one provider.
///
/// The secret never lives here: API keys are kept in the Keychain, this
/// record only says whether the provider is on and which language it
/// prefers.
public struct SubtitleProviderConfig: Codable, Sendable, Equatable, Identifiable {
    public let id: SubtitleProviderID
    /// False keeps the provider configured but out of the searches.
    public var isEnabled: Bool
    /// ISO 639-1 code the provider should search first. nil = follow the
    /// app's subtitle language preference.
    public var language: String?
    /// When the user added it — shown in the settings list.
    public var addedAt: Date

    public init(
        id: SubtitleProviderID,
        isEnabled: Bool = true,
        language: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.language = language
        self.addedAt = addedAt
    }
}

/// Problems the settings screen reports to the user.
public enum SubtitleProviderError: LocalizedError, Equatable {
    /// The provider id is not in the catalogue.
    case unknownProvider
    /// The provider is already configured.
    case duplicateProvider
    /// A built-in provider cannot be deleted.
    case notRemovable
    /// The provider needs a key and none was given.
    case missingAPIKey
    /// The key has spaces in it — it is always a single token.
    case invalidAPIKey
    /// The key could not be saved (Keychain refused).
    case secretStorageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownProvider:
            "Ese proveedor no existe."
        case .duplicateProvider:
            "El proveedor ya está en la lista."
        case .notRemovable:
            "Este proveedor viene con la app y no se puede eliminar; puedes desactivarlo."
        case .missingAPIKey:
            "Falta la API key del proveedor."
        case .invalidAPIKey:
            "La API key no es válida: no puede contener espacios."
        case .secretStorageFailed(let detail):
            "No se pudo guardar la API key: \(detail)"
        }
    }
}
