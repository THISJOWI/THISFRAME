import XCTest
@testable import ThisJellyFixCore

/// Layout rules for the media cards.
///
/// The regression these guard: an episode card used to take a fixed width
/// (240 pt on iOS, 320 pt on macOS) whatever the container offered, so in
/// the adaptive grids it overflowed its column — sometimes by 150 % — and
/// collided with the next cell.
final class MediaCardLayoutTests: XCTestCase {
    private let server = URL(string: "http://localhost:8096")!

    // MARK: - Shape

    func testShapeAspectRatios() {
        XCTAssertEqual(MediaCardLayout.Shape.landscape.aspectRatio, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(MediaCardLayout.Shape.poster.aspectRatio, 2.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - Height

    func testHeightDerivesFromTheShape() {
        // 16:9 tile.
        XCTAssertEqual(MediaCardLayout.height(forWidth: 240, shape: .landscape), 135)
        XCTAssertEqual(MediaCardLayout.height(forWidth: 320, shape: .landscape), 180)
        // 2:3 poster.
        XCTAssertEqual(MediaCardLayout.height(forWidth: 170, shape: .poster), 255)
    }

    func testHeightOfZeroWidthIsZero() {
        XCTAssertEqual(MediaCardLayout.height(forWidth: 0, shape: .landscape), 0)
        XCTAssertEqual(MediaCardLayout.height(forWidth: -10, shape: .poster), 0)
    }

    // MARK: - Which image the server is asked for

    func testLandscapePrefersAReal16x9Frame() {
        XCTAssertEqual(
            JellyfinArtwork.preferredImageType(shape: .landscape, availableTypes: ["Thumb", "Backdrop", "Primary"]),
            "Thumb"
        )
        XCTAssertEqual(
            JellyfinArtwork.preferredImageType(shape: .landscape, availableTypes: ["Backdrop", "Primary"]),
            "Backdrop"
        )
    }

    func testLandscapeFallsBackToThePortraitPoster() {
        XCTAssertEqual(
            JellyfinArtwork.preferredImageType(shape: .landscape, availableTypes: ["Primary"]),
            "Primary"
        )
        XCTAssertNil(
            JellyfinArtwork.preferredImageType(shape: .landscape, availableTypes: [])
        )
    }

    func testPosterAlwaysWantsThePrimaryImage() {
        XCTAssertEqual(
            JellyfinArtwork.preferredImageType(shape: .poster, availableTypes: ["Thumb", "Backdrop", "Primary"]),
            "Primary"
        )
        // A 16:9 backdrop cropped into a poster frame would leave a sliver:
        // the poster shape prefers no image at all.
        XCTAssertNil(
            JellyfinArtwork.preferredImageType(shape: .poster, availableTypes: ["Backdrop"])
        )
    }

    // MARK: - The URL

    func testArtworkURLAsksTheServerForTheExactAspect() throws {
        let item = JellyfinMediaItem(
            id: "item-1",
            name: "Episodio",
            type: "Episode",
            imageTags: ["Primary": "tag"]
        )
        let url = try XCTUnwrap(
            JellyfinArtwork.url(for: item, serverURL: server, shape: .landscape, targetWidth: 120)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/Items/item-1/Images/Primary")
        // Twice the point size for Retina, cropped to the shape by the server
        // so the client never re-crops (and never blows the poster up).
        XCTAssertEqual(items["fillWidth"], "240")
        XCTAssertEqual(items["fillHeight"], "135")
        XCTAssertEqual(items["quality"], "90")
    }

    func testPosterArtworkUsesTwoToThree() throws {
        let item = JellyfinMediaItem(id: "m", name: "Película", type: "Movie", imageTags: ["Primary": "t"])
        let url = try XCTUnwrap(
            JellyfinArtwork.url(for: item, serverURL: server, shape: .poster, targetWidth: 150)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["fillWidth"], "300")
        XCTAssertEqual(items["fillHeight"], "450")
    }

    func testItemWithoutImagesHasNoArtwork() {
        let item = JellyfinMediaItem(id: "m", name: "Sin imagen", type: "Movie")
        XCTAssertNil(item.artworkURL(serverURL: server))
    }

    func testEpisodeArtworkIsLandscapeAndMovieArtworkIsPoster() throws {
        let episode = JellyfinMediaItem(id: "e", name: "Ep", type: "Episode", imageTags: ["Primary": "t"])
        let movie = JellyfinMediaItem(id: "m", name: "Movie", type: "Movie", imageTags: ["Primary": "t"])

        let episodeURL = try XCTUnwrap(episode.artworkURL(serverURL: server))
        let movieURL = try XCTUnwrap(movie.artworkURL(serverURL: server))

        let episodeItems = queryItems(episodeURL)
        let movieItems = queryItems(movieURL)
        // Different boxes, each with its own ratio: 16:9 for the episode,
        // 2:3 for the movie.
        XCTAssertEqual(
            Double(episodeItems["fillWidth"]!)! / Double(episodeItems["fillHeight"]!)!,
            16.0 / 9.0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            Double(movieItems["fillWidth"]!)! / Double(movieItems["fillHeight"]!)!,
            2.0 / 3.0,
            accuracy: 0.01
        )
    }

    func testBackdropOnlyItemStillHasLandscapeArtwork() throws {
        let item = JellyfinMediaItem(
            id: "s",
            name: "Serie",
            type: "Series",
            imageTags: ["Primary": "t"],
            backdropImageTags: ["b1"]
        )
        let url = try XCTUnwrap(item.artworkURL(serverURL: server, shape: .landscape))
        XCTAssertTrue(url.path.hasSuffix("/Images/Backdrop"))
    }

    // MARK: - Helpers

    private func queryItems(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
