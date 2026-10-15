import XCTest
@testable import ThisJellyFixCore

final class SavedServersStoreTests: XCTestCase {
    private func memoryKeychain() -> KeychainStoring {
        KeychainStore(service: "test.savedservers.\(UUID().uuidString)", systemKeychain: false)
    }

    func testUpsertDedupesByNormalizedURL() {
        let a = JellyfinServer(baseURL: URL(string: "https://example.com")!, name: "A")
        let b = JellyfinServer(baseURL: URL(string: "https://example.com/")!, name: "B")
        let result = SavedServersStore.upsert([a], server: b)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "B")
        XCTAssertEqual(result[0].id, a.id, "debe conservar id estable para SwiftUI")
    }

    func testSaveLoadRoundtrip() throws {
        let kc = memoryKeychain()
        let servers = [
            JellyfinServer(baseURL: URL(string: "https://one.example")!, name: "One"),
            JellyfinServer(baseURL: URL(string: "http://192.168.1.10:8096")!, name: "Local"),
        ]
        try SavedServersStore.save(servers, to: kc)
        let loaded = SavedServersStore.load(from: kc)
        XCTAssertEqual(loaded, servers)
    }

    func testLoadEmptyWhenNothingStored() {
        XCTAssertTrue(SavedServersStore.load(from: memoryKeychain()).isEmpty)
    }

    func testMigrateLegacySingleURL() throws {
        let kc = memoryKeychain()
        try kc.save(key: KeychainKey.serverURL, value: "https://legacy.example/")
        let migrated = SavedServersStore.migrateLegacyIfNeeded(current: [], keychain: kc)
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated[0].baseURL, URL(string: "https://legacy.example"))
    }

    func testMigrateDoesNotDuplicate() throws {
        let kc = memoryKeychain()
        try kc.save(key: KeychainKey.serverURL, value: "https://example.com")
        let existing = [JellyfinServer(baseURL: URL(string: "https://example.com")!, name: "X")]
        let result = SavedServersStore.migrateLegacyIfNeeded(current: existing, keychain: kc)
        XCTAssertEqual(result, existing)
    }

    func testDedupeKeyIgnoresCaseAndTrailingSlash() {
        let k1 = SavedServersStore.dedupeKey(for: URL(string: "https://Example.COM/")!)
        let k2 = SavedServersStore.dedupeKey(for: URL(string: "https://example.com")!)
        XCTAssertEqual(k1, k2)
    }
}
