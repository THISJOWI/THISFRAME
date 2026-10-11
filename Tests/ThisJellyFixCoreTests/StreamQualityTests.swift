import XCTest
@testable import ThisJellyFixCore

final class StreamQualityTests: XCTestCase {
    func testAutoHasNoBitrateCap() {
        XCTAssertNil(StreamQuality.auto.maxBitrate)
    }

    func testCappedOptionsDecreaseMonotonically() {
        let capped = StreamQuality.allCases.filter { $0.maxBitrate != nil }
        // Automático is the only uncapped option.
        XCTAssertEqual(StreamQuality.allCases.count - capped.count, 1)

        let bitrates = capped.map { $0.maxBitrate! }
        for pair in zip(bitrates, bitrates.dropFirst()) {
            XCTAssertGreaterThan(pair.0, pair.1, "bitrate ladder must descend")
        }
    }

    func testLabelsAreSpanishAndUnique() {
        let labels = StreamQuality.allCases.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count)
        XCTAssertEqual(StreamQuality.auto.label, "Automático")
        XCTAssertEqual(StreamQuality.q1080.label, "1080p")
        XCTAssertEqual(StreamQuality.q720.label, "720p")
        XCTAssertEqual(StreamQuality.q480.label, "480p")
        XCTAssertEqual(StreamQuality.q360.label, "360p")
    }
}
