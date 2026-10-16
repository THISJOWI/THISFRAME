import XCTest
@testable import ThisJellyFixFeature
import ThisJellyFixCore

/// El picker debe listar TODAS las pistas declaradas: bitmap → burn-in vía
/// transcode; texto fallido → reintento. Nada desaparece en silencio.
@MainActor
final class PlayerViewModelSubtitleAvailabilityTests: XCTestCase {
    private func stream(
        language: String?,
        codec: String?,
        index: Int?,
        title: String? = nil
    ) -> MediaStream {
        MediaStream(
            type: "Subtitle",
            language: language,
            title: title,
            index: index,
            codec: codec
        )
    }

    func testBitmapListedForBurnIn() {
        let rows = PlayerViewModel.classifyUnservedSubtitles(
            serverStreams: [stream(language: "es", codec: "pgssub", index: 4)],
            loadedServerIndices: [],
            failedServerIndices: []
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, 4)
        XCTAssertEqual(rows[0].reason, .bitmapRequiresTranscode)
        XCTAssertEqual(rows[0].codec, "PGSSUB")
    }

    func testFailedTextListedForRetry() {
        let rows = PlayerViewModel.classifyUnservedSubtitles(
            serverStreams: [stream(language: "es", codec: "ass", index: 3)],
            loadedServerIndices: [],
            failedServerIndices: [3]
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].reason, .downloadFailed)
    }

    func testLoadedTracksOmitted() {
        let rows = PlayerViewModel.classifyUnservedSubtitles(
            serverStreams: [
                stream(language: "es", codec: "ass", index: 3),
                stream(language: "es", codec: "pgssub", index: 4),
            ],
            loadedServerIndices: [3],
            failedServerIndices: [3, 4]
        )
        // La 3 ya cargó (aunque fallara antes): solo queda la bitmap.
        XCTAssertEqual(rows.map(\.id), [4])
    }

    func testLoadingTracksNotListed() {
        // Ni cargada ni fallida = aún en vuelo: no parpadear en el picker.
        let rows = PlayerViewModel.classifyUnservedSubtitles(
            serverStreams: [stream(language: "es", codec: "srt", index: 2)],
            loadedServerIndices: [],
            failedServerIndices: []
        )
        XCTAssertTrue(rows.isEmpty)
    }

    func testIndexlessStreamsSkipped() {
        let rows = PlayerViewModel.classifyUnservedSubtitles(
            serverStreams: [stream(language: "es", codec: "srt", index: nil)],
            loadedServerIndices: [],
            failedServerIndices: []
        )
        XCTAssertTrue(rows.isEmpty)
    }

    func testNonSubtitleStreamsIgnored() {
        let audio = MediaStream(type: "Audio", language: "es", index: 1)
        let rows = PlayerViewModel.classifyUnservedSubtitles(
            serverStreams: [audio],
            loadedServerIndices: [],
            failedServerIndices: [1]
        )
        XCTAssertTrue(rows.isEmpty)
    }
}
