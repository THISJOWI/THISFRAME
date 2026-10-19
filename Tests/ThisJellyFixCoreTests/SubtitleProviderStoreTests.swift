import XCTest
@testable import ThisJellyFixCore

/// Persistence and validation of the user's subtitle providers.
final class SubtitleProviderStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var keychain: InMemoryKeychain!
    private var store: SubtitleProviderStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SubtitleProviderStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        keychain = InMemoryKeychain()
        store = SubtitleProviderStore(defaults: defaults, keychain: keychain)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Defaults

    func testServerProviderIsAlwaysOfferedAndNeedsNoCredentials() {
        let configs = store.effectiveConfigs()
        XCTAssertEqual(configs.first?.id, .jellyfinServer)
        XCTAssertTrue(configs.first?.isEnabled == true)
        XCTAssertTrue(store.isConfigured(.jellyfinServer))
    }

    func testNoClientSideProviderUntilItIsAdded() {
        XCTAssertTrue(store.configs().isEmpty)
        XCTAssertEqual(store.effectiveConfigs().count, 1)
    }

    // MARK: - Adding

    func testAddProviderPersistsIt() throws {
        let config = try store.add(.openSubtitles)
        XCTAssertEqual(config.id, .openSubtitles)
        XCTAssertTrue(config.isEnabled)

        let reloaded = SubtitleProviderStore(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.config(for: .openSubtitles)?.id, .openSubtitles)
        XCTAssertEqual(reloaded.effectiveConfigs().count, 2)
    }

    func testAddingTheSameProviderTwiceIsRejected() throws {
        _ = try store.add(.openSubtitles)
        XCTAssertThrowsError(try store.add(.openSubtitles)) { error in
            XCTAssertEqual(error as? SubtitleProviderError, .duplicateProvider)
        }
        // The list still holds a single entry.
        XCTAssertEqual(store.configs().filter { $0.id == .openSubtitles }.count, 1)
    }

    func testAddKeepsTheLanguage() throws {
        _ = try store.add(.openSubtitles, language: "es")
        XCTAssertEqual(store.config(for: .openSubtitles)?.language, "es")
    }

    /// The switch in the form must be honoured: a provider the user turned
    /// off must not be stored as enabled.
    func testAddKeepsTheEnabledFlag() throws {
        let config = try store.add(.openSubtitles, isEnabled: false)
        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(store.config(for: .openSubtitles)?.isEnabled, false)
        XCTAssertFalse(store.effectiveConfigs().first { $0.id == .openSubtitles }?.isEnabled == true)
    }

    // MARK: - Updating

    func testUpdateChangesTheStoredConfig() throws {
        _ = try store.add(.openSubtitles)
        var config = try XCTUnwrap(store.config(for: .openSubtitles))
        config.isEnabled = false
        config.language = "en"
        try store.update(config)

        let reloaded = SubtitleProviderStore(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.config(for: .openSubtitles)?.isEnabled, false)
        XCTAssertEqual(reloaded.config(for: .openSubtitles)?.language, "en")
    }

    func testUpdateOfUnknownProviderThrows() {
        let config = SubtitleProviderConfig(id: .openSubtitles)
        XCTAssertThrowsError(try store.update(config)) { error in
            XCTAssertEqual(error as? SubtitleProviderError, .unknownProvider)
        }
    }

    func testDisablingTheServerProviderIsRemembered() throws {
        try store.setEnabled(false, for: .jellyfinServer)
        XCTAssertEqual(store.effectiveConfigs().first?.isEnabled, false)
    }

    // MARK: - Removing

    func testRemoveDropsTheProviderAndItsSecret() throws {
        _ = try store.add(.openSubtitles)
        try store.setAPIKey("secret", for: .openSubtitles)

        try store.remove(.openSubtitles)

        XCTAssertNil(store.config(for: .openSubtitles))
        XCTAssertNil(store.apiKey(for: .openSubtitles))
    }

    func testTheServerProviderCannotBeRemoved() {
        XCTAssertThrowsError(try store.remove(.jellyfinServer)) { error in
            XCTAssertEqual(error as? SubtitleProviderError, .notRemovable)
        }
    }

    // MARK: - Secrets

    func testAPIKeyRoundTripsThroughTheKeychain() throws {
        try store.setAPIKey("abc123", for: .openSubtitles)
        XCTAssertEqual(store.apiKey(for: .openSubtitles), "abc123")
        XCTAssertTrue(store.isConfigured(.openSubtitles))
    }

    func testAPIKeyIsNeverWrittenToThePreferences() throws {
        try store.setAPIKey("super-secret", for: .openSubtitles)
        let raw = defaults.string(forKey: SubtitleProviderStore.DefaultsKey.providers) ?? ""
        let data = defaults.data(forKey: SubtitleProviderStore.DefaultsKey.providers) ?? Data()
        XCTAssertFalse(raw.contains("super-secret"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("super-secret"))
    }

    func testAPIKeyIsTrimmed() throws {
        try store.setAPIKey("  abc123  ", for: .openSubtitles)
        XCTAssertEqual(store.apiKey(for: .openSubtitles), "abc123")
    }

    func testAPIKeyWithSpacesIsRejected() {
        XCTAssertThrowsError(try store.setAPIKey("abc 123", for: .openSubtitles)) { error in
            XCTAssertEqual(error as? SubtitleProviderError, .invalidAPIKey)
        }
        XCTAssertNil(store.apiKey(for: .openSubtitles))
    }

    func testEmptyAPIKeyClearsTheSecret() throws {
        try store.setAPIKey("abc123", for: .openSubtitles)
        try store.setAPIKey("", for: .openSubtitles)
        XCTAssertNil(store.apiKey(for: .openSubtitles))
        XCTAssertFalse(store.isConfigured(.openSubtitles))
    }

    func testProviderWithoutKeyIsNotConfigured() {
        XCTAssertFalse(store.isConfigured(.openSubtitles))
    }

    // MARK: - Catalogue

    func testCatalogueDescribesEveryProvider() {
        for id in SubtitleProviderID.allCases {
            let descriptor = SubtitleProviderCatalog.descriptor(for: id)
            XCTAssertNotNil(descriptor, "missing descriptor for \(id)")
            XCTAssertFalse(descriptor?.displayName.isEmpty == true)
        }
    }

    func testOnlyTheServerProviderIsNotRemovable() {
        let removable = SubtitleProviderCatalog.addable.map(\.id)
        XCTAssertFalse(removable.contains(.jellyfinServer))
        XCTAssertTrue(removable.contains(.openSubtitles))
    }

    func testOnlyClientSideProvidersNeedAKey() {
        XCTAssertFalse(SubtitleProviderCatalog.descriptor(for: .jellyfinServer)!.requiresAPIKey)
        XCTAssertTrue(SubtitleProviderCatalog.descriptor(for: .openSubtitles)!.requiresAPIKey)
    }
}
