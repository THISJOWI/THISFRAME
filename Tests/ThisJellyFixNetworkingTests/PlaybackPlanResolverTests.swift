import XCTest
@testable import ThisJellyFixNetworking
import ThisJellyFixCore

/// El plan de reproducción pre-resuelve SOLO audio. Los subtítulos van
/// siempre con -1 (invariante anti-dobles): muxear el sub hacía que AVPlayer
/// lo autoseleccionara al abrir, por encima de los apagados de la nativa.
final class PlaybackPlanResolverTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    private func planJSON(audios: String, subs: String) -> String {
        """
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","Name":"video","MediaStreams":[\(audios)\(subs)]}]}
        """
    }

    private let audiosMismatch = """
        {"Type":"Audio","Language":"de","Index":1,"IsDefault":true},\
        {"Type":"Audio","Language":"es","Index":2}
        """

    private let audiosMatch = """
        {"Type":"Audio","Language":"es","Index":1,"IsDefault":true},\
        {"Type":"Audio","Language":"de","Index":2}
        """

    private let subTracks = """
        ,{"Type":"Subtitle","Language":"es","Index":3,"Codec":"ass"},\
        {"Type":"Subtitle","Language":"es","Index":4,"Codec":"srt"}
        """

    override func setUp() {
        super.setUp()
        // Preferencia determinista: español en todo.
        LanguagePreferences(preferredAudio: "es", preferredSubtitles: "es").save(to: .standard)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguagePreferences.Key.audio)
        UserDefaults.standard.removeObject(forKey: LanguagePreferences.Key.subtitles)
        super.tearDown()
    }

    func testMismatchRefetchesWithAudioIndexAndMinusOneSubtitle() async throws {
        let session = MockPlanSession(data: Data(planJSON(audios: audiosMismatch, subs: subTracks).utf8))
        let client = JellyfinPlaybackClient(session: session)
        let plan = try await resolvePlaybackPlan(
            client: client, userId: "u", serverURL: server, token: "t", itemId: "i", quality: .auto
        )
        XCTAssertEqual(plan.audioServerIndex, 2)
        XCTAssertEqual(session.bodies.count, 2)
        // Segunda llamada: pide el audio español…
        XCTAssertEqual(session.bodies[1]["AudioStreamIndex"] as? Int, 2)
        // …pero NUNCA un subtítulo (aunque haya match es): -1 siempre.
        XCTAssertEqual(session.bodies[0]["SubtitleStreamIndex"] as? Int, -1)
        XCTAssertEqual(session.bodies[1]["SubtitleStreamIndex"] as? Int, -1)
    }

    func testMatchNeedsSingleRoundtrip() async throws {
        let session = MockPlanSession(data: Data(planJSON(audios: audiosMatch, subs: subTracks).utf8))
        let client = JellyfinPlaybackClient(session: session)
        let plan = try await resolvePlaybackPlan(
            client: client, userId: "u", serverURL: server, token: "t", itemId: "i", quality: .auto
        )
        XCTAssertEqual(plan.audioServerIndex, 1)
        XCTAssertEqual(session.bodies.count, 1)
        XCTAssertNil(session.bodies[0]["AudioStreamIndex"])
        XCTAssertEqual(session.bodies[0]["SubtitleStreamIndex"] as? Int, -1)
    }
}

private final class MockPlanSession: JellyfinNetworkSession, @unchecked Sendable {
    let mockData: Data
    private(set) var bodies: [[String: Any]] = []

    init(data: Data) { self.mockData = data }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
        bodies.append(body)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (mockData, response)
    }
}
