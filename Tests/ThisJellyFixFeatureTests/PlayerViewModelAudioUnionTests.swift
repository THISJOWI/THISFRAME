import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixCore

/// La unión engine+servidor del picker de audio: un remux/transcode trae un
/// solo audio servido y el resto solo existe en `MediaStreams` — exponer
/// solo el engine esconde pistas ("a veces faltan").
@MainActor
final class PlayerViewModelAudioUnionTests: XCTestCase {
    private func serverAudio(language: String?, index: Int, isDefault: Bool? = nil) -> MediaStream {
        MediaStream(type: "Audio", language: language, index: index, isDefault: isDefault)
    }

    private func engineAudio(name: String, language: String?, id: Int = 0) -> AudioTrack {
        AudioTrack(id: id, name: name, language: language, engineIndex: id)
    }

    func testUnionMapsServedTrackToEngineOption() {
        let vm = PlayerViewModel()
        vm.configureMediaStreams([
            serverAudio(language: "de", index: 1, isDefault: true),
            serverAudio(language: "es", index: 2),
        ])
        vm.noteServedAudioServerIndex(1)
        let union = vm.unionAudioTracks(engineTracks: [engineAudio(name: "German", language: "de")])
        XCTAssertEqual(union.count, 2)
        // La servida (de) mapea al engine 0: selección directa.
        XCTAssertEqual(union[0].engineIndex, 0)
        XCTAssertEqual(union[0].serverIndex, 1)
        // La no servida (es) queda marcada para switch vía servidor.
        XCTAssertNil(union[1].engineIndex)
        XCTAssertEqual(union[1].serverIndex, 2)
        XCTAssertTrue(union[1].needsServerSwitch)
        XCTAssertFalse(union[0].needsServerSwitch)
    }

    func testUnionPositionalWhenCountsAgree() {
        let vm = PlayerViewModel()
        vm.configureMediaStreams([
            serverAudio(language: "de", index: 1),
            serverAudio(language: "es", index: 2),
        ])
        let union = vm.unionAudioTracks(engineTracks: [
            engineAudio(name: "A", language: "de", id: 0),
            engineAudio(name: "B", language: "es", id: 1),
        ])
        XCTAssertEqual(union.count, 2)
        XCTAssertEqual(union[0].engineIndex, 0)
        XCTAssertEqual(union[1].engineIndex, 1)
    }

    func testUnionFallsBackToEngineWithoutServerMetadata() {
        let vm = PlayerViewModel()
        vm.configureMediaStreams([])
        let union = vm.unionAudioTracks(engineTracks: [engineAudio(name: "Track 1", language: nil)])
        XCTAssertEqual(union.count, 1)
        XCTAssertEqual(union[0].engineIndex, 0)
        XCTAssertFalse(union[0].needsServerSwitch)
    }

    func testSelectAudioMarksServedRowWithoutEngineCall() async {
        // Fila servida con engineIndex: selección directa, sin re-fetch.
        let vm = PlayerViewModel()
        let track = AudioTrack(id: 0, name: "Alemán", language: "de", serverIndex: 1, engineIndex: 0)
        await vm.selectAudioTrack(track)
        XCTAssertEqual(vm.selectedAudioTrackIndex, 0)
    }
}
