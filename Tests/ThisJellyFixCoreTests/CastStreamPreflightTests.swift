import XCTest
@testable import ThisJellyFixCore

/// T-cast2 — preflight de URL Cast. El receptor descarga la URL él mismo:
/// loopback y URLs sin ApiKey deben rechazarse ANTES de cargar en el
/// Chromecast (donde el fallo es un 401/opaco sin posibilidad de log).
final class CastStreamPreflightTests: XCTestCase {
    func testLanHTTPWithApiKeyIsOK() {
        let url = URL(string: "http://192.168.1.10:8096/Videos/abc/stream.m3u8?ApiKey=secret")!
        XCTAssertEqual(CastStreamPreflight.validateForReceiver(url), .ok)
    }

    func testHTTPSAfterIsOK() {
        let url = URL(string: "https://jellyfin.dominio.io/Videos/abc/stream?ApiKey=secret")!
        XCTAssertEqual(CastStreamPreflight.validateForReceiver(url), .ok)
    }

    func testLocalhostRejected() {
        let url = URL(string: "http://localhost:8096/Videos/abc/stream?ApiKey=x")!
        let verdict = CastStreamPreflight.validate(url)
        guard case .rejected(let reason) = verdict else {
            return XCTFail("localhost debe rechazarse")
        }
        XCTAssertTrue(reason.contains("localhost"))
    }

    func testLoopbackIPIPv4Rejected() {
        let url = URL(string: "http://127.0.0.1:8096/a?ApiKey=x")!
        guard case .rejected = CastStreamPreflight.validate(url) else {
            return XCTFail("127.0.0.1 debe rechazarse")
        }
    }

    func testNonHTTPSchemeRejected() {
        let url = URL(string: "file:///var/media/peli.mp4")!
        guard case .rejected = CastStreamPreflight.validate(url) else {
            return XCTFail("file:// debe rechazarse")
        }
    }

    func testMissingHostRejected() {
        let url = URL(string: "http:///path-only?ApiKey=x")!
        guard case .rejected = CastStreamPreflight.validate(url) else {
            return XCTFail("URL sin host debe rechazarse")
        }
    }

    func testMissingApiKeyRejected() {
        let url = URL(string: "http://192.168.1.10:8096/Videos/abc/stream.m3u8")!
        let verdict = CastStreamPreflight.validateForReceiver(url)
        guard case .rejected(let reason) = verdict else {
            return XCTFail("URL sin ApiKey debe rechazarse")
        }
        XCTAssertTrue(reason.contains("401"))
    }

    func testApiKeyVariantsRecognized() {
        // StreamURLResolver acepta ApiKey/api_key/apiKey — el preflight debe
        // reconocer las mismas variantes.
        for name in ["ApiKey", "api_key", "apiKey", "APIKEY"] {
            let url = URL(string: "http://192.168.1.10/a?\(name)=tok")!
            XCTAssertTrue(CastStreamPreflight.carriesApiKey(url), name)
        }
    }

    func testReasonNeverContainsToken() {
        // La URL con error lleva token — el motivo expuesto no debe filtrarlo.
        let url = URL(string: "http://localhost:8096/a?ApiKey=SUPERSECRET")!
        if case .rejected(let reason) = CastStreamPreflight.validateForReceiver(url) {
            XCTAssertFalse(reason.contains("SUPERSECRET"))
        } else {
            XCTFail("esperaba rejected")
        }
    }
}
