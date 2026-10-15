import XCTest
import ThisJellyFixCore
import ThisJellyFixNetworking
@testable import ThisJellyFixFeature

private struct StubProbe: JellyfinServerProbing {
    var name: String = "TestServer"
    func publicInfo(at baseURL: URL) async throws -> JellyfinPublicInfo {
        let json = """
        {"ServerName": "\(name)", "Version": "10.9", "Id": "abc"}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(JellyfinPublicInfo.self, from: json)
    }
}

@MainActor
final class ServerConnectionModelTests: XCTestCase {
    func testConnectPersistsServer() async {
        let kc = MockKeychain()
        let model = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        model.address = "jellyfin.example.com"
        await model.connect()
        XCTAssertNotNil(model.server)
        XCTAssertEqual(model.savedServers.count, 1)
        // Persistido: lista + actual
        XCTAssertNotNil(kc.read(key: KeychainKey.savedServers))
        XCTAssertEqual(kc.read(key: KeychainKey.serverURL), "https://jellyfin.example.com")
        // Re-lanzamiento: se recupera
        let relaunched = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        XCTAssertNotNil(relaunched.server)
        XCTAssertEqual(relaunched.savedServers.count, 1)
    }

    func testConnectDuplicateDoesNotDuplicate() async {
        let kc = MockKeychain()
        let model = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        model.address = "https://example.com"
        await model.connect()
        model.address = "https://example.com/"
        await model.connect()
        XCTAssertEqual(model.savedServers.count, 1)
    }

    func testMalformedURLDoesNotCorruptExisting() async {
        let kc = MockKeychain()
        let model = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        model.address = "https://good.example"
        await model.connect()
        XCTAssertEqual(model.savedServers.count, 1)
        model.address = "ftp://bad.example"
        await model.connect()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.savedServers.count, 1, "URL malformada no debe corromper guardados")
        XCTAssertEqual(SavedServersStore.load(from: kc).count, 1)
    }

    func testRemoveKeepsRest() async {
        let kc = MockKeychain()
        let model = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        model.address = "https://one.example"
        await model.connect()
        model.address = "https://two.example"
        await model.connect()
        XCTAssertEqual(model.savedServers.count, 2)
        let firstId = model.savedServers[0].id
        model.removeSavedServer(id: firstId)
        XCTAssertEqual(model.savedServers.count, 1)
        // Sobrevive a reinicio
        let relaunched = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        XCTAssertEqual(relaunched.savedServers.count, 1)
    }

    func testDisconnectKeepsListButClearsCurrent() async {
        let kc = MockKeychain()
        let model = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        model.address = "https://example.com"
        await model.connect()
        model.disconnect()
        XCTAssertNil(model.server)
        XCTAssertEqual(model.savedServers.count, 1, "disconnect no debe borrar guardados")
        XCTAssertNil(kc.read(key: KeychainKey.serverURL))
        // Re-lanzamiento: lista sigue, sin fantasma auto-seleccionado
        let relaunched = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        XCTAssertNil(relaunched.server)
        XCTAssertEqual(relaunched.savedServers.count, 1)
    }

    func testLegacyMigration() async {
        let kc = MockKeychain(storage: [KeychainKey.serverURL: "https://legacy.example/"])
        let model = ServerConnectionModel(probe: StubProbe(), keychain: kc)
        XCTAssertEqual(model.savedServers.count, 1)
        XCTAssertEqual(model.savedServers[0].baseURL.absoluteString, "https://legacy.example")
    }
}
