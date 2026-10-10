import Foundation
import Observation
import ThisJellyFixCore
import ThisJellyFixNetworking

@MainActor
@Observable
final class AuthModel {
    // MARK: - Login fields
    var username = ""
    var password = ""
    var isAuthenticating = false
    var errorMessage: String?

    // MARK: - Auth state
    var isAuthenticated = false
    var currentUser: JellyfinUser?

    // MARK: - Dependencies
    private let authClient: any JellyfinAuthenticating
    private let keychain: any KeychainStoring
    private let deviceId: String

    init(
        authClient: any JellyfinAuthenticating = JellyfinAuthClient(),
        keychain: any KeychainStoring = KeychainStore(),
        deviceId: String? = nil
    ) {
        self.authClient = authClient
        self.keychain = keychain
        self.deviceId = deviceId ?? DeviceIdentifier(keychain: keychain).current()

        // Restore synchronously (three Keychain reads, no network) so the FIRST
        // frame is already Home. Restoring after first paint flashed LoginView
        // and rebuilt the whole tree three times on every launch.
        if let token = keychain.read(key: KeychainKey.accessToken),
           let userId = keychain.read(key: KeychainKey.userId),
           let userName = keychain.read(key: KeychainKey.userName),
           !token.isEmpty {
            currentUser = JellyfinUser(id: userId, name: userName)
            isAuthenticated = true
        }
    }

    // MARK: - Login

    func login(serverURL: URL) async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let result = try await authClient.authenticate(
                username: username,
                password: password,
                serverURL: serverURL,
                deviceId: deviceId
            )

            // Persist to Keychain
            try keychain.save(key: KeychainKey.accessToken, value: result.accessToken)
            try keychain.save(key: KeychainKey.userId, value: result.user.id)
            try keychain.save(key: KeychainKey.userName, value: result.user.name)
            try keychain.save(key: KeychainKey.serverURL, value: serverURL.absoluteString)

            currentUser = result.user
            isAuthenticated = true

            // Clear form
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Restore session

    func restoreSession(serverURL: URL) async -> Bool {
        guard let token = keychain.read(key: KeychainKey.accessToken),
              let userId = keychain.read(key: KeychainKey.userId),
              let userName = keychain.read(key: KeychainKey.userName)
        else {
            return false
        }

        // Validate the stored token against the server: a stale/revoked token
        // used to be trusted until the first 401, stranding the user on a
        // broken Home. Invalid session → clean slate (login screen).
        do {
            let user = try await authClient.validateToken(
                userId: userId, serverURL: serverURL, token: token, deviceId: deviceId
            )
            currentUser = user.name.isEmpty
                ? JellyfinUser(id: user.id, name: userName, primaryImageTag: user.primaryImageTag)
                : user
            isAuthenticated = true
            return true
        } catch {
            TJFLog("restoreSession: token validation failed — \(error.localizedDescription)")
            logout()
            return false
        }
    }

    // MARK: - Logout

    func logout() {
        try? keychain.delete(key: KeychainKey.accessToken)
        try? keychain.delete(key: KeychainKey.userId)
        try? keychain.delete(key: KeychainKey.userName)
        try? keychain.delete(key: KeychainKey.serverURL)

        currentUser = nil
        isAuthenticated = false
        username = ""
        password = ""
        errorMessage = nil

        SpotlightIndexer.shared.deleteAll()
    }
}
