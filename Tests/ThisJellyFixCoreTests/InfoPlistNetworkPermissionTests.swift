import XCTest

/// Radarr/Sonarr live on the user's LAN, so both apps need the local
/// network permission keys. Without `NSLocalNetworkUsageDescription` the
/// system **denies the connection silently — no dialog ever appears**,
/// which is impossible to debug from the UI.
final class InfoPlistNetworkPermissionTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/ThisJellyFixCoreTests/File.swift
            .deletingLastPathComponent()          // …/Tests/ThisJellyFixCoreTests
            .deletingLastPathComponent()          // …/Tests
            .deletingLastPathComponent()          // repo root
    }

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(object as? [String: Any], "Expected dictionary in \(relativePath)")
    }

    func testMacOSDeclaresLocalNetworkUsageDescription() throws {
        let info = try plist("Apps/macOS/Info.plist")
        let reason = info["NSLocalNetworkUsageDescription"] as? String
        XCTAssertNotNil(reason, "macOS app must ask for the local network permission")
        XCTAssertFalse((reason ?? "").isEmpty)
    }

    func testIOSDeclaresLocalNetworkUsageDescription() throws {
        let info = try plist("Apps/iOS/Info.plist")
        let reason = info["NSLocalNetworkUsageDescription"] as? String
        XCTAssertNotNil(reason, "iOS app must ask for the local network permission")
        XCTAssertFalse((reason ?? "").isEmpty)
    }

    /// Radarr/Sonarr on `http://192.168.x.x:7878` are plain HTTP: ATS blocks
    /// them unless local networking is explicitly allowed.
    func testIOSAllowsPlainHTTPOnTheLocalNetwork() throws {
        let info = try plist("Apps/iOS/Info.plist")
        let ats = try XCTUnwrap(info["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(ats["NSAllowsLocalNetworking"] as? Bool, true)
    }

    func testMacOSSandboxAllowsOutgoingConnections() throws {
        let entitlements = try plist("Apps/macOS/ThisJellyfix.entitlements")
        XCTAssertEqual(
            entitlements["com.apple.security.network.client"] as? Bool, true,
            "Sandboxed macOS app cannot reach Radarr/Sonarr without network.client"
        )
    }

    func testIOSDeclaresBonjourServicesForLocalNetworkPrompt() throws {
        let info = try plist("Apps/iOS/Info.plist")
        let bonjourServices = try XCTUnwrap(info["NSBonjourServices"] as? [String])
        XCTAssertTrue(bonjourServices.contains("_http._tcp"), "Must contain _http._tcp")
        XCTAssertTrue(bonjourServices.contains("_bonjour._tcp"), "Must contain _bonjour._tcp")
    }

    func testMacOSDeclaresBonjourServicesForLocalNetworkPrompt() throws {
        let info = try plist("Apps/macOS/Info.plist")
        let bonjourServices = try XCTUnwrap(info["NSBonjourServices"] as? [String])
        XCTAssertTrue(bonjourServices.contains("_http._tcp"), "Must contain _http._tcp")
        XCTAssertTrue(bonjourServices.contains("_bonjour._tcp"), "Must contain _bonjour._tcp")
    }

    /// NSBonjourServices entries must be bare service types: a trailing dot
    /// ("_lnp._tcp.") is a malformed registration and the entry silently
    /// stops matching — the AirPlay/discovery permission prompt never fires.
    func testIOSBonjourServicesHaveNoTrailingDot() throws {
        let info = try plist("Apps/iOS/Info.plist")
        let services = try XCTUnwrap(info["NSBonjourServices"] as? [String])
        for service in services {
            XCTAssertFalse(service.hasSuffix("."), "\(service) must not end with '.'")
        }
    }

    func testMacOSBonjourServicesHaveNoTrailingDot() throws {
        let info = try plist("Apps/macOS/Info.plist")
        let services = try XCTUnwrap(info["NSBonjourServices"] as? [String])
        for service in services {
            XCTAssertFalse(service.hasSuffix("."), "\(service) must not end with '.'")
        }
    }

    /// Every activity type the code can publish/receive must be declared —
    /// an undeclared NSUserActivityType is dropped by the system on arrival.
    func testBothPlistsDeclareAllHandoffActivityTypes() throws {
        let expected: Set<String> = [
            "com.thisjellyfix.activity.browsing",
            "com.thisjellyfix.activity.detail",
            "com.thisjellyfix.activity.playing",
        ]
        for path in ["Apps/iOS/Info.plist", "Apps/macOS/Info.plist"] {
            let info = try plist(path)
            let declared = try XCTUnwrap(info["NSUserActivityTypes"] as? [String], "\(path)")
            XCTAssertEqual(Set(declared), expected, "\(path) NSUserActivityTypes mismatch")
        }
    }
}
