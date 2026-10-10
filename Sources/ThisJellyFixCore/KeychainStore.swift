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

    public init(service: String = "com.thisjellyfix.auth", systemKeychain: Bool? = nil) {
        self.service = service
        // Test runners (XCTest loaded or its config env) get the memory
        // backend unless TJF_REAL_KEYCHAIN=1 explicitly opts in
        // (e.g. TJF_REAL_KEYCHAIN=1 swift test --filter KeychainStoreTests).
        // `!isTestRunner` keeps the shipped app on the real keychain.
        let isTestRunner = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        self.systemKeychain = systemKeychain
            ?? (ProcessInfo.processInfo.environment["TJF_REAL_KEYCHAIN"] != nil || !isTestRunner)
        // One-shot upgrade of items written before iCloud sync: once a
        // synchronizable copy exists the legacy query stops matching.
        // Reads the REAL keychain — never allowed under a test runner.
        if self.systemKeychain { migrateIfNeeded() }
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

    public func save(key: String, value: String) throws {
        guard systemKeychain else {
            Self.memory.save(service: service, key: key, value: value)
            return
        }
        deleteIfExists(key: key)

        guard let data = value.data(using: .utf8) else { return }

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
    }

    public func read(key: String) -> String? {
        guard systemKeychain else {
            return Self.memory.read(service: service, key: key)
        }
        var query = Self.baseQuery(service: service, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return string
    }

    public func delete(key: String) throws {
        guard systemKeychain else {
            Self.memory.delete(service: service, key: key)
            return
        }
        let query = Self.baseQuery(service: service, key: key)

        let status = SecItemDelete(query as CFDictionary)
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

    // MARK: - Migration

    /// Re-saves any item written without iCloud sync so it can start
    /// syncing. Runs at most once per install: a synchronizable item is no
    /// longer matched by the legacy query.
    private func migrateIfNeeded() {
        let keys = [
            KeychainKey.accessToken,
            KeychainKey.userId,
            KeychainKey.userName,
            KeychainKey.serverURL,
            KeychainKey.deviceId,
        ]

        for key in keys {
            // 1. Legacy item = default group, explicitly NOT synchronizable.
            var legacyQuery = Self.baseQuery(service: service, key: key)
            legacyQuery[kSecAttrSynchronizable as String] = false
            legacyQuery[kSecReturnData as String] = true
            legacyQuery[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: AnyObject?
            let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let value = String(data: data, encoding: .utf8)
            else { continue }

            // 2. Drop the stale copy, then write the synchronizable one.
            try? delete(key: key)
            try? save(key: key, value: value)
        }
    }

    // MARK: - Private

    private func deleteIfExists(key: String) {
        try? delete(key: key)
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
