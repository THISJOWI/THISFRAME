import Foundation

// MARK: - Saved servers store (Prioridad 1)
//
// Persiste la LISTA de dominios del usuario como JSON bajo una sola clave
// de Keychain. La clave histórica `serverURL` se conserva como "servidor
// actual" por compatibilidad con AuthModel/restoreSession; la lista es la
// fuente de verdad para el selector.

public enum SavedServersStore {
    public static var listKey: String { KeychainKey.savedServers }

    private struct CodableServer: Codable {
        var id: UUID
        var baseURL: URL
        var name: String
    }

    /// Normaliza para deduplicar: minúsculas + sin `/` final.
    public static func dedupeKey(for url: URL) -> String {
        var s = url.absoluteString.lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public static func load(from keychain: any KeychainStoring) -> [JellyfinServer] {
        guard let raw = keychain.read(key: KeychainKey.savedServers),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CodableServer].self, from: data)
        else { return [] }
        return decoded.map { JellyfinServer(id: $0.id, baseURL: $0.baseURL, name: $0.name) }
    }

    public static func save(_ servers: [JellyfinServer], to keychain: any KeychainStoring) throws {
        let encodable = servers.map { CodableServer(id: $0.id, baseURL: $0.baseURL, name: $0.name) }
        let data = try JSONEncoder().encode(encodable)
        guard let raw = String(data: data, encoding: .utf8) else { return }
        try keychain.save(key: KeychainKey.savedServers, value: raw)
    }

    /// Inserta o actualiza por URL normalizada. Devuelve la lista resultante.
    /// Conserva el `id` existente para no romper identidad de SwiftUI.
    public static func upsert(_ servers: [JellyfinServer], server: JellyfinServer) -> [JellyfinServer] {
        let key = dedupeKey(for: server.baseURL)
        var result = servers
        if let idx = result.firstIndex(where: { dedupeKey(for: $0.baseURL) == key }) {
            let existing = result[idx]
            result[idx] = JellyfinServer(id: existing.id, baseURL: server.baseURL, name: server.name)
        } else {
            result.append(server)
        }
        return result
    }

    /// Migra la clave histórica de un solo servidor a la lista.
    /// No duplica si la URL ya está en la lista.
    public static func migrateLegacyIfNeeded(current: [JellyfinServer], keychain: any KeychainStoring) -> [JellyfinServer] {
        guard current.isEmpty,
              let urlString = keychain.read(key: KeychainKey.serverURL)
        else { return current }
        let url: URL? = (try? ServerAddress.normalizedURL(from: urlString)) ?? URL(string: urlString)
        guard let url else { return current }
        let name = url.host ?? "Server"
        return [JellyfinServer(baseURL: url, name: name)]
    }
}
