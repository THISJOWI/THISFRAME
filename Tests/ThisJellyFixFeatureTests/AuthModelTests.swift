import XCTest
import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

@MainActor
final class AuthModelTests: XCTestCase {
    private let serverURL = URL(string: "http://localhost:8096")!

    private func makeKeychain() -> MockKeychain {
        MockKeychain(storage: [
            KeychainKey.accessToken: "stored-token",
            KeychainKey.userId: "u1",
            KeychainKey.userName: "Joel",
        ])
    }

    func testRestoreSessionInvalidTokenClearsKeychainAndReturnsFalse() async {
        let keychain = makeKeychain()
        let authClient = MockAuthClient(
            validateTokenResult: .failure(AuthError.invalidCredentials)
        )
        let model = AuthModel(authClient: authClient, keychain: keychain, deviceId: "dev-1")

        let restored = await model.restoreSession(serverURL: serverURL)

        XCTAssertFalse(restored)
        XCTAssertNil(keychain.read(key: KeychainKey.accessToken))
        XCTAssertFalse(model.isAuthenticated)
        XCTAssertNil(model.currentUser)
        XCTAssertEqual(authClient.validateTokenCallCount, 1)
    }

    func testRestoreSessionValidTokenPopulatesUserAndReturnsTrue() async {
        let keychain = makeKeychain()
        let authClient = MockAuthClient(
            validateTokenResult: .success(JellyfinUser(id: "u1", name: "Joel"))
        )
        let model = AuthModel(authClient: authClient, keychain: keychain, deviceId: "dev-1")

        let restored = await model.restoreSession(serverURL: serverURL)

        XCTAssertTrue(restored)
        XCTAssertTrue(model.isAuthenticated)
        XCTAssertEqual(model.currentUser?.name, "Joel")
        XCTAssertEqual(model.currentUser?.id, "u1")
        // Valid session keeps the stored token.
        XCTAssertEqual(keychain.read(key: KeychainKey.accessToken), "stored-token")
    }
}
