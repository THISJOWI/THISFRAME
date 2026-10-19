import Foundation

/// Where the user's subtitle providers live.
///
/// The list (which providers exist, whether they are on, which language they
/// prefer) is plain data and goes to `UserDefaults`. The API keys are
/// secrets and go to the Keychain, one item per provider — the same split
/// `IntegrationConfig` already uses for TMDB/Radarr/Sonarr.
public struct SubtitleProviderStore: Sendable {
    public enum DefaultsKey {
        public static let providers = "com.thisjellyfix.subtitleproviders.list"
    }

    /// Keychain account for a provider's API key.
    public static func keychainKey(for id: SubtitleProviderID) -> String {
        "com.thisjellyfix.subtitleproviders.apiKey.\(id.rawValue)"
    }

    /// Matches the entitlements and `IntegrationConfig.appGroupSuite`.
    public static let appGroupSuite = "group.com.thisjellyfix"

    private let defaults: UserDefaults
    private let keychain: any KeychainStoring

    public init(
        defaults: UserDefaults = UserDefaults(suiteName: SubtitleProviderStore.appGroupSuite) ?? .standard,
        keychain: any KeychainStoring = KeychainStore(service: "com.thisjellyfix.subtitleproviders")
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

    // MARK: - List

    /// The providers the user configured, oldest first.
    public func configs() -> [SubtitleProviderConfig] {
        guard let data = defaults.data(forKey: DefaultsKey.providers) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([SubtitleProviderConfig].self, from: data) else {
            // Corrupt payload: start from scratch rather than crash the
            // settings screen on every launch.
            TJFLog("subtitleproviders: stored list unreadable — resetting")
            return []
        }
        return decoded.sorted { $0.addedAt < $1.addedAt }
    }

    public func config(for id: SubtitleProviderID) -> SubtitleProviderConfig? {
        configs().first { $0.id == id }
    }

    /// Every provider the app offers, with the user's settings applied.
    ///
    /// The server provider is always first: it needs no credentials, so it
    /// is usable out of the box even if the user never touches the screen.
    public func effectiveConfigs() -> [SubtitleProviderConfig] {
        var result: [SubtitleProviderConfig] = []
        let stored = configs()
        if let serverConfig = stored.first(where: { $0.id == .jellyfinServer }) {
            result.append(serverConfig)
        } else {
            result.append(SubtitleProviderConfig(id: .jellyfinServer, isEnabled: true))
        }
        result.append(contentsOf: stored.filter { $0.id != .jellyfinServer })
        return result
    }

    // MARK: - Mutations

    /// Add a provider. Fails when it is already configured — the settings
    /// screen must never end up with the same provider twice.
    @discardableResult
    public func add(
        _ id: SubtitleProviderID,
        language: String? = nil
    ) throws -> SubtitleProviderConfig {
        guard SubtitleProviderCatalog.descriptor(for: id) != nil else {
            throw SubtitleProviderError.unknownProvider
        }
        var list = configs()
        guard !list.contains(where: { $0.id == id }) else {
            throw SubtitleProviderError.duplicateProvider
        }
        let config = SubtitleProviderConfig(
            id: id,
            isEnabled: true,
            language: language.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        list.append(config)
        try save(list)
        return config
    }

    /// Replace a provider's settings.
    public func update(_ config: SubtitleProviderConfig) throws {
        var list = configs()
        guard let index = list.firstIndex(where: { $0.id == config.id }) else {
            throw SubtitleProviderError.unknownProvider
        }
        list[index] = config
        try save(list)
    }

    /// Switch a provider on or off. The built-in server provider is stored
    /// like any other so it can be switched off too.
    public func setEnabled(_ isEnabled: Bool, for id: SubtitleProviderID) throws {
        if let existing = config(for: id) {
            var updated = existing
            updated.isEnabled = isEnabled
            try update(updated)
            return
        }
        guard id == .jellyfinServer else { throw SubtitleProviderError.unknownProvider }
        try save(configs() + [SubtitleProviderConfig(id: id, isEnabled: isEnabled)])
    }

    /// Remove a provider and the secret it owns.
    ///
    /// The secret goes first: if the Keychain refuses, the provider stays in
    /// the list and the user can try again, instead of leaving a key
    /// nobody can reach any more.
    public func remove(_ id: SubtitleProviderID) throws {
        guard SubtitleProviderCatalog.descriptor(for: id)?.isRemovable == true else {
            throw SubtitleProviderError.notRemovable
        }
        do {
            try keychain.delete(key: Self.keychainKey(for: id))
        } catch {
            throw SubtitleProviderError.secretStorageFailed(error.localizedDescription)
        }
        try save(configs().filter { $0.id != id })
    }

    // MARK: - Secrets

    /// The provider's API key, nil when it has none.
    public func apiKey(for id: SubtitleProviderID) -> String? {
        guard let value = keychain.read(key: Self.keychainKey(for: id)) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Store (or clear) the provider's API key.
    ///
    /// An empty value clears the key; a value with inner spaces is rejected
    /// because every provider issues single-token keys.
    public func setAPIKey(_ key: String?, for id: SubtitleProviderID) throws {
        guard SubtitleProviderCatalog.descriptor(for: id) != nil else {
            throw SubtitleProviderError.unknownProvider
        }
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            do {
                try keychain.delete(key: Self.keychainKey(for: id))
            } catch {
                throw SubtitleProviderError.secretStorageFailed(error.localizedDescription)
            }
            return
        }
        guard !trimmed.contains(where: { $0.isWhitespace }) else {
            throw SubtitleProviderError.invalidAPIKey
        }
        do {
            try keychain.save(key: Self.keychainKey(for: id), value: trimmed)
        } catch {
            throw SubtitleProviderError.secretStorageFailed(error.localizedDescription)
        }
    }

    /// True when the provider can be used: either it needs no key, or the
    /// key is there.
    public func isConfigured(_ id: SubtitleProviderID) -> Bool {
        guard let descriptor = SubtitleProviderCatalog.descriptor(for: id) else { return false }
        guard descriptor.requiresAPIKey else { return true }
        return apiKey(for: id) != nil
    }

    // MARK: - Private

    private func save(_ list: [SubtitleProviderConfig]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(list)
        defaults.set(data, forKey: DefaultsKey.providers)
    }
}
