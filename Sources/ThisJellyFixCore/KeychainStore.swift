import Foundation
import Security

// MARK: - Protocol

public protocol KeychainStoring: Sendable {
    func save(key: String, value: String) throws
    func read(key: String) -> String?
    func delete(key: String) throws
    func deleteAll() throws
}

// MARK: - Keys

public enum KeychainKey {
    public static let accessToken = "com.thisjellyfix.auth.accessToken"
    public static let userId      = "com.thisjellyfix.auth.userId"
    public static let userName    = "com.thisjellyfix.auth.userName"
    public static let serverURL   = "com.thisjellyfix.auth.serverURL"
    public static let deviceId    = "com.thisjellyfix.auth.deviceId"
}

// MARK: - Constants

private enum KeychainConstants {
    /// Items are stored in the app's **default** keychain group.
    ///
    /// They used to be written with `kSecAttrAccessGroup = "group.…"`, but
    /// an App Group id is not a keychain access group: the signed build is
    /// only entitled to the groups listed in `keychain-access-groups`
    /// (`$(AppIdentifierPrefix)com.thisjellyfix`), so every call failed with
    /// -34018 and the caller's `try?` swallowed it. Net effect on device:
    /// API keys and the session token were never stored.
    ///
    /// iCloud Keychain (`kSecAttrSynchronizable`) is what still shares
    /// secrets across the user's devices — it needs no shared group.
    static let useSynchronizable = true
}

// MARK: - Implementation

public struct KeychainStore: KeychainStoring {
    private let service: String
    /// false → operate on a process-local dictionary instead of SecItem.
    /// The login keychain's ACL is per code signature, so xctest re-prompts
    /// for the app's REAL items on every rebuild ("allow always" never
    /// sticks) — one dialog per key, forever. Tests must never see those
    /// dialogs: `swift test`/`xcodebuild test` run fully keychain-free.
    private let systemKeychain: Bool

    public init(service: String = "com.thisjellyfix.auth.v2", systemKeychain: Bool? = nil) {
        self.service = service
        // Test runners (XCTest loaded or its config env) get the memory
        // backend unless TJF_REAL_KEYCHAIN=1 explicitly opts in
        // (e.g. TJF_REAL_KEYCHAIN=1 swift test --filter KeychainStoreTests).
        // `!isTestRunner` keeps the shipped app on the real keychain.
        let isTestRunner = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        self.systemKeychain = systemKeychain
            ?? (ProcessInfo.processInfo.environment["TJF_REAL_KEYCHAIN"] != nil || !isTestRunner)
        // One-shot upgrade of items written before iCloud sync. Runs at most
        // once PER PROCESS per service (was: once per KeychainStore init, and
        // the init runs per network request via DeviceIdentifier — the key
        // source of the keychain prompt storm).
        if self.systemKeychain {
            migrateIfNeeded()
            adoptFromLegacyServiceIfNeeded()
        }
    }

    /// One-shot adoption of items written under the pre-rotation service
    /// name (`com.thisjellyfix.auth`). That service's items were poisoned by
    /// a test runner (ACL pinned to a retired xctest cdhash — "Allow" never
    /// survives a rebuild, so the prompt came back every launch). Items the
    /// APP can still read fail-fast are copied over; poisoned ones are left
    /// behind untouched (their owner is a dead binary — only Keychain
    /// Access could ever delete them) and the user simply logs in again
    /// once. Runs at most once per process.
    private func adoptFromLegacyServiceIfNeeded() {
        guard service == "com.thisjellyfix.auth.v2",
              Self.session.markMigrated("legacy-adopt:\(service)") else { return }
        let legacy = KeychainStore(service: "com.thisjellyfix.auth", systemKeychain: true)
        for key in [KeychainKey.accessToken, KeychainKey.userId,
                    KeychainKey.userName, KeychainKey.serverURL, KeychainKey.deviceId] {
            // Fail-fast lookup: a poisoned legacy item returns nil here
            // WITHOUT ever raising a dialog.
            if let value = legacy.lookup(key: key, interactive: false).value,
               Self.session.value(legacy.cacheKey(key)) == nil {
                try? save(key: key, value: value)
                TJFLog("keychain: adopted \(key) from legacy service")
            }
        }
    }

    // MARK: - Test backend (never prompts)

    private static let memory = MemoryKeychain()

    /// Process-local keychain stand-in: `service\u{0}key` → value.
    /// `@unchecked Sendable` behind an NSLock — static shared across the
    /// whole test process (matches how one login keychain behaves).
    private final class MemoryKeychain: @unchecked Sendable {
        private var items: [String: String] = [:]
        private let lock = NSLock()

        private func mapKey(_ service: String, _ key: String) -> String {
            "\(service)\u{0}\(key)"
        }

        func read(service: String, key: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return items[mapKey(service, key)]
        }

        func save(service: String, key: String, value: String) {
            lock.lock(); defer { lock.unlock() }
            items[mapKey(service, key)] = value
        }

        func delete(service: String, key: String) {
            lock.lock(); defer { lock.unlock() }
            items.removeValue(forKey: mapKey(service, key))
        }

        func deleteAll(service: String) {
            lock.lock(); defer { lock.unlock() }
            items = items.filter { !$0.key.hasPrefix("\(service)\u{0}") }
        }
    }

    // MARK: - Session state (real keychain only)

    /// Process-wide session state for the REAL keychain backend:
    ///
    /// - `values` caches successful reads — `DeviceIdentifier().current()`
    ///   runs per network request and `KeychainStore().read(...)` used to
    ///   run inside SwiftUI `body`; both become dictionary lookups.
    /// - `interactiveAttempts` bounds the number of USER-DIALOG operations
    ///   per key per process (fail-fast reads, recovery reads, recovery
    ///   deletes). A poisoned item can prompt at most twice per launch,
    ///   never once per request.
    /// - `migrated` marks services whose legacy→sync upgrade already ran.
    ///
    /// An item whose ACL belongs to another binary (a stale test-runner
    /// cdhash) is healed on first contact: read interactively once, then
    /// delete+re-add so the item carries the app's OWN ACL (stable across
    /// rebuilds). See `heal`.
    private static let session = SessionCache()

    private final class SessionCache: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]
        private var interactiveAttempts: [String: Int] = [:]
        private var migrated: Set<String> = []

        func value(_ cacheKey: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return values[cacheKey]
        }

        func setValue(_ value: String, _ cacheKey: String) {
            lock.lock(); defer { lock.unlock() }
            values[cacheKey] = value
        }

        func removeValue(_ cacheKey: String) {
            lock.lock(); defer { lock.unlock() }
            values.removeValue(forKey: cacheKey)
        }

        /// True while the per-key interactive budget (2: one recovery read +
        /// one recovery delete) is left.
        func beginInteractive(_ cacheKey: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let used = interactiveAttempts[cacheKey, default: 0]
            guard used < 2 else { return false }
            interactiveAttempts[cacheKey] = used + 1
            return true
        }

        func markMigrated(_ service: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return migrated.insert(service).inserted
        }
    }

    // MARK: - KeychainStoring

    /// Query for one account, in the app's default keychain group.
    /// Exposed for tests: the absence of `kSecAttrAccessGroup` is the fix.
    static func baseQuery(service: String, key: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    /// Query matching both the iCloud and the local copy of an account.
    /// Without `kSecAttrSynchronizableAny` a query matches ONLY the
    /// non-synchronizable variant — invisible on devices where the synced
    /// item is the one that exists.
    static func anySyncQuery(service: String, key: String) -> [String: Any] {
        var query = baseQuery(service: service, key: key)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        return query
    }

    public func save(key: String, value: String) throws {
        guard systemKeychain else {
            Self.memory.save(service: service, key: key, value: value)
            return
        }
        guard let data = value.data(using: .utf8) else { return }

        // Remove any existing copy FIRST (both sync and local variants) and
        // PROPAGATE the failure: the old `try?` here is what let a poisoned
        // item survive forever — delete failed silently, the subsequent add
        // hit errSecDuplicateItem, save "failed" invisibly, and every read
        // re-prompted. `delete` does its own bounded interactive recovery.
        try delete(key: key)

        var query = Self.baseQuery(service: service, key: key)
        query[kSecValueData as String] = data

        // kSecAttrSynchronizable is not supported on the tvOS simulator; guard
        // it so a Debug build there doesn't fail the whole save.
        #if !targetEnvironment(simulator)
        if KeychainConstants.useSynchronizable {
            query[kSecAttrSynchronizable as String] = true
        }
        #endif

        var status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // iCloud Keychain can be unavailable (no iCloud account, or a
            // profile without the entitlement). Losing sync is acceptable;
            // losing the secret is not.
            var local = Self.baseQuery(service: service, key: key)
            local[kSecValueData as String] = data
            status = SecItemAdd(local as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        Self.session.setValue(value, cacheKey(key))
    }

    public func read(key: String) -> String? {
        guard systemKeychain else {
            return Self.memory.read(service: service, key: key)
        }
        if let cached = Self.session.value(cacheKey(key)) {
            return cached
        }
        // 1. Fail-fast: never allowed to display a dialog. The prompt storm
        //    (one dialog per request while an item ACL was foreign) dies here.
        switch lookup(key: key, interactive: false) {
        case .found(let value):
            Self.session.setValue(value, cacheKey(key))
            return value
        case .notFound:
            return nil
        case .authRequired:
            break // 2. bounded recovery below
        case .failed:
            return nil
        }
        // 2. Bounded interactive recovery: ONE dialog per key per process for
        //    a foreign-ACL item (e.g. written by a test runner before test
        //    isolation, so its ACL names a dead cdhash — "Always Allow" from
        //    any build never sticks). Heal the item so it stops prompting.
        guard Self.session.beginInteractive(cacheKey(key)) else {
            TJFLog("keychain: \(key) denied and interactive budget spent — no further prompts")
            return nil
        }
        switch lookup(key: key, interactive: true) {
        case .found(let value):
            TJFLog("keychain: interactive recovery for \(key) — rewriting item with app-owned ACL")
            do {
                try heal(key: key, value: value)
            } catch {
                // Value is still good this launch; the cached copy plus the
                // attempt budget keep the dialog from repeating either way.
                TJFLog("keychain: heal for \(key) failed: \(error.localizedDescription)")
            }
            Self.session.setValue(value, cacheKey(key))
            return value
        case .notFound, .failed:
            return nil
        case .authRequired:
            TJFLog("keychain: interactive recovery for \(key) not permitted")
            return nil
        }
    }

    public func delete(key: String) throws {
        guard systemKeychain else {
            Self.memory.delete(service: service, key: key)
            return
        }
        var status = performDelete(key: key, interactive: false)
        if isAuthStatus(status), Self.session.beginInteractive(cacheKey(key)) {
            // Foreign-ACL item: one dialog, then it's gone (and `save`
            // re-adds it under the app's own ACL).
            status = performDelete(key: key, interactive: true)
        }
        Self.session.removeValue(cacheKey(key))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    public func deleteAll() throws {
        guard systemKeychain else {
            Self.memory.deleteAll(service: service)
            return
        }
        // Fetch all accounts for this service, then delete each individually.
        // SecItemDelete with class+service alone is unreliable on some macOS versions.
        var query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecReturnAttributes as String:   true,
            kSecMatchLimit as String:         kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            return
        }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            try delete(key: account)
        }
    }

    // MARK: - Lookup

    private enum Lookup {
        case found(String)
        case notFound
        /// Item exists but its ACL won't let THIS binary read it without a
        /// user dialog (`kSecUseAuthenticationUIFail` refused the UI).
        case authRequired
        case failed(OSStatus)

        var value: String? {
            if case .found(let s) = self { return s }
            return nil
        }
    }

    private func lookup(key: String, interactive: Bool) -> Lookup {
        var query = Self.anySyncQuery(service: service, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !interactive {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8)
            else { return .failed(errSecSuccess) }
            return .found(string)
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed, errSecAuthFailed:
            return .authRequired
        default:
            return .failed(status)
        }
    }

    /// Delete both variants (sync + local) of one account.
    private func performDelete(key: String, interactive: Bool) -> OSStatus {
        var query = Self.anySyncQuery(service: service, key: key)
        if !interactive {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        return SecItemDelete(query as CFDictionary)
    }

    private func isAuthStatus(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecAuthFailed
    }

    /// Rewrite one account under the app's OWN ACL.
    ///
    /// The item's access control list names the identity that last touched
    /// it. When that identity is foreign (a retired test-runner cdhash), the
    /// app can read it only after the user approves a dialog — and approval
    /// never survives a rebuild. Deleting and re-adding from inside the app
    /// stamps the item with the app's designated requirement, which is
    /// stable across rebuilds: the dialog stops permanently.
    private func heal(key: String, value: String) throws {
        let status = performDelete(key: key, interactive: true)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        try save(key: key, value: value)
    }

    // MARK: - Migration

    /// Re-saves any item written without iCloud sync so it can start
    /// syncing. Runs at most once PER PROCESS per service: a synchronizable
    /// item is no longer matched by the legacy query, but the init that
    /// calls this runs constantly (per request via DeviceIdentifier), and
    /// every SecItemCopyMatching against a foreign-ACL item was another
    /// dialog candidate.
    private func migrateIfNeeded() {
        guard Self.session.markMigrated(service) else { return }

        let keys = [
            KeychainKey.accessToken,
            KeychainKey.userId,
            KeychainKey.userName,
            KeychainKey.serverURL,
            KeychainKey.deviceId,
        ]

        for key in keys {
            // 1. Legacy item = default group, explicitly NOT synchronizable.
            //    Fail-fast: migration must never prompt — a foreign-ACL item
            //    is left alone and healed by the normal read path instead.
            var legacyQuery = Self.baseQuery(service: service, key: key)
            legacyQuery[kSecAttrSynchronizable as String] = false
            legacyQuery[kSecReturnData as String] = true
            legacyQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            legacyQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

            var result: AnyObject?
            let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let value = String(data: data, encoding: .utf8)
            else { continue }

            // 2. Drop the stale copy, then write the synchronizable one.
            //    Fail-fast + budgeted; a poisoned legacy item surfaces no
            //    dialog from migration.
            _ = performDelete(key: key, interactive: false)
            try? save(key: key, value: value)
        }
    }

    // MARK: - Private

    private func cacheKey(_ key: String) -> String {
        "\(service)\u{0}\(key)"
    }
}

// MARK: - Errors

public enum KeychainError: LocalizedError, Equatable {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Error guardando en Keychain (código \(status))"
        case .deleteFailed(let status):
            "Error eliminando de Keychain (código \(status))"
        }
    }
}
