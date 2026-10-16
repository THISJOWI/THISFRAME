import XCTest
@testable import ThisJellyFixCore

final class PlaybackStreamPickerTests: XCTestCase {
    private func audio(language: String?, isDefault: Bool? = nil, index: Int) -> MediaStream {
        MediaStream(type: "Audio", language: language, index: index, isDefault: isDefault)
    }

    // MARK: - Audio index

    func testAudioNilWhenPreferredIsServerDefault() {
        let streams = [audio(language: "es", isDefault: true, index: 1), audio(language: "en", index: 2)]
        // Pedirlo sería un roundtrip inútil: el servidor ya sirve ese.
        XCTAssertNil(PlaybackStreamPicker.audioIndex(in: streams, preferred: "es"))
    }

    func testAudioReturnsIndexWhenPreferredDiffersFromDefault() {
        let streams = [audio(language: "de", isDefault: true, index: 1), audio(language: "es", index: 2)]
        XCTAssertEqual(PlaybackStreamPicker.audioIndex(in: streams, preferred: "es"), 2)
    }

    func testAudioNilWithoutMatch() {
        let streams = [audio(language: "de", isDefault: true, index: 1)]
        XCTAssertNil(PlaybackStreamPicker.audioIndex(in: streams, preferred: "ja"))
    }

    func testAudioNilWithoutPreference() {
        let streams = [audio(language: "de", isDefault: true, index: 1)]
        XCTAssertNil(PlaybackStreamPicker.audioIndex(in: streams, preferred: nil))
    }

    func testDefaultAudioPrefersFlaggedTrack() {
        let streams = [audio(language: "de", index: 1), audio(language: "en", isDefault: true, index: 2)]
        XCTAssertEqual(PlaybackStreamPicker.defaultAudioIndex(in: streams), 2)
    }

    func testDefaultAudioFallsBackToFirst() {
        let streams = [audio(language: "de", index: 5), audio(language: "en", index: 6)]
        XCTAssertEqual(PlaybackStreamPicker.defaultAudioIndex(in: streams), 5)
    }
}
