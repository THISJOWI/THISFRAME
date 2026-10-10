import Foundation
import ThisJellyFixCore
import ThisJellyFixNetworking

/// In-memory Keychain — tests never touch the real keychain.
final class MockKeychain: KeychainStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    init(storage: [String: String] = [:]) {
        self.storage = storage
    }

    func save(key: String, value: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func read(key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func delete(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }

    func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}

/// Scriptable auth client — validateToken returns a preset result.
final class MockAuthClient: JellyfinAuthenticating, @unchecked Sendable {
    var validateTokenResult: Result<JellyfinUser, Error>
    private(set) var validateTokenCallCount = 0

    init(validateTokenResult: Result<JellyfinUser, Error>) {
        self.validateTokenResult = validateTokenResult
    }

    func authenticate(
        username: String,
        password: String,
        serverURL: URL,
        deviceId: String
    ) async throws -> AuthenticationResult {
        fatalError("authenticate is not exercised in these tests")
    }

    func validateToken(
        userId: String,
        serverURL: URL,
        token: String,
        deviceId: String
    ) async throws -> JellyfinUser {
        validateTokenCallCount += 1
        return try validateTokenResult.get()
    }
}
