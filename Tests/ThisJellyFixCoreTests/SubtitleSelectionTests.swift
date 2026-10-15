import XCTest
@testable import ThisJellyFixCore

final class SubtitleSelectionTests: XCTestCase {
    private func stream(
        language: String?,
        forced: Bool? = nil,
        sdh: Bool? = nil,
        isDefault: Bool? = nil,
        index: Int? = nil
    ) -> MediaStream {
        MediaStream(
            type: "Subtitle",
            language: language,
            index: index,
            isForced: forced,
            isDefault: isDefault,
            isHearingImpaired: sdh
        )
    }

    func testPrefersFullOverForcedSameLanguage() {
        let streams = [
            stream(language: "es", forced: true, index: 0),
            stream(language: "es", forced: false, index: 1),
        ]
        XCTAssertEqual(SubtitleSelection.bestStreamIndex(in: streams, preferred: "es"), 1)
    }

    func testPrefersNonSDHOverSDHSameLanguage() {
        let streams = [
            stream(language: "es", sdh: true, index: 0),
            stream(language: "es", sdh: false, index: 1),
        ]
        XCTAssertEqual(SubtitleSelection.bestStreamIndex(in: streams, preferred: "es"), 1)
    }

    func testForcedOnlyLanguageStillSelectable() {
        // No full alternative: forced is better than nothing (never dropped).
        let streams = [stream(language: "es", forced: true, index: 5)]
        XCTAssertEqual(SubtitleSelection.bestStreamIndex(in: streams, preferred: "es"), 0)
    }

    func testPrefersDefaultAmongEquals() {
        let streams = [
            stream(language: "es", isDefault: false, index: 0),
            stream(language: "es", isDefault: true, index: 1),
        ]
        XCTAssertEqual(SubtitleSelection.bestStreamIndex(in: streams, preferred: "es"), 1)
    }

    func testNoMatchReturnsNil() {
        let streams = [stream(language: "en", index: 0)]
        XCTAssertNil(SubtitleSelection.bestStreamIndex(in: streams, preferred: "es"))
    }

    func testNilPreferenceReturnsNil() {
        let streams = [stream(language: "es", index: 0)]
        XCTAssertNil(SubtitleSelection.bestStreamIndex(in: streams, preferred: nil))
    }

    func testIgnoresNonSubtitleStreams() {
        let audio = MediaStream(type: "Audio", language: "es", index: 0)
        let sub = stream(language: "es", index: 1)
        XCTAssertEqual(SubtitleSelection.bestStreamIndex(in: [audio, sub], preferred: "es"), 1)
    }

    func testDecodesHearingImpairedFlag() throws {
        let json = """
        {"Type":"Subtitle","Language":"es","Index":2,"IsForced":false,"IsDefault":true,"IsHearingImpaired":true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MediaStream.self, from: json)
        XCTAssertEqual(decoded.isHearingImpaired, true)
        XCTAssertEqual(decoded.isDefault, true)
        XCTAssertEqual(decoded.isForced, false)
    }
}
