import Foundation

/// Builds the URL of the artwork that matches the shape a card draws.
///
/// One place decides *which* image the server should send (`Thumb` /
/// `Backdrop` for a 16:9 frame, `Primary` for a 2:3 poster) and *how big*
/// it should cut it, so every surface asks for the same picture and none of
/// them ends up stretching a portrait poster into a landscape tile.
///
/// The crop is asked from the server (`fillWidth`/`fillHeight`): Jellyfin
/// returns an image with exactly the requested aspect ratio, so the client
/// draws it 1:1 instead of re-cropping (and blowing up) a portrait poster
/// into a 16:9 box.
public enum JellyfinArtwork {
    /// Point size the app renders a card at, per shape. The server is asked
    /// for twice this (Retina) so the picture stays sharp without bloating
    /// the image cache.
    public static func defaultTargetWidth(for shape: MediaCardLayout.Shape) -> CGFloat {
        switch shape {
        case .poster: 170
        case .landscape: 320
        }
    }

    /// Image types the item actually has.
    public static func availableTypes(for item: JellyfinMediaItem) -> [String] {
        var types = Array((item.imageTags ?? [:]).keys)
        if !(item.backdropImageTags ?? []).isEmpty, !types.contains("Backdrop") {
            types.append("Backdrop")
        }
        return types
    }

    /// Image types the episode actually has.
    public static func availableTypes(for episode: JellyfinEpisode) -> [String] {
        Array((episode.imageTags ?? [:]).keys)
    }

    /// URL of the artwork for `item` in the requested shape, or nil when the
    /// item has no image at all.
    public static func url(
        for item: JellyfinMediaItem,
        serverURL: URL,
        shape: MediaCardLayout.Shape,
        targetWidth: CGFloat? = nil
    ) -> URL? {
        url(
            itemId: item.id,
            serverURL: serverURL,
            shape: shape,
            availableTypes: availableTypes(for: item),
            targetWidth: targetWidth
        )
    }

    /// URL of the artwork for `episode` in the requested shape.
    public static func url(
        for episode: JellyfinEpisode,
        serverURL: URL,
        shape: MediaCardLayout.Shape,
        targetWidth: CGFloat? = nil
    ) -> URL? {
        url(
            itemId: episode.id,
            serverURL: serverURL,
            shape: shape,
            availableTypes: availableTypes(for: episode),
            targetWidth: targetWidth
        )
    }

    /// The image the server should send for `shape`, given what the item has.
    ///
    /// A 16:9 frame prefers a real landscape image (`Thumb`, then
    /// `Backdrop`) and only falls back to the portrait `Primary`, which the
    /// server then crops to 16:9. A 2:3 poster always wants `Primary`.
    static func preferredImageType(
        shape: MediaCardLayout.Shape,
        availableTypes: [String]
    ) -> String? {
        let has: (String) -> Bool = { availableTypes.contains($0) }
        switch shape {
        case .landscape:
            if has("Thumb") { return "Thumb" }
            if has("Backdrop") { return "Backdrop" }
            if has("Primary") { return "Primary" }
            return nil
        case .poster:
            if has("Primary") { return "Primary" }
            if has("Backdrop") { return "Backdrop" }
            return nil
        }
    }

    private static func url(
        itemId: String,
        serverURL: URL,
        shape: MediaCardLayout.Shape,
        availableTypes: [String],
        targetWidth: CGFloat?
    ) -> URL? {
        guard let imageType = preferredImageType(shape: shape, availableTypes: availableTypes) else {
            return nil
        }
        let points = targetWidth ?? defaultTargetWidth(for: shape)
        let pixelWidth = max(64, Int((points * 2).rounded()))
        let pixelHeight = max(36, Int((Double(pixelWidth) / shape.aspectRatio).rounded()))
        return serverURL
            .appendingPathComponent("Items/\(itemId)/Images/\(imageType)")
            .appending(queryItems: [
                URLQueryItem(name: "fillWidth", value: String(pixelWidth)),
                URLQueryItem(name: "fillHeight", value: String(pixelHeight)),
                URLQueryItem(name: "quality", value: "90"),
            ])
    }
}

public extension JellyfinMediaItem {
    /// Artwork for a card showing this item.
    ///
    /// Episodes are rendered as 16:9 frames and everything else as 2:3
    /// posters, so the picture always matches the box it is drawn in. Pass
    /// `shape` to override (the "continue watching" row is always 16:9).
    func artworkURL(
        serverURL: URL,
        shape: MediaCardLayout.Shape? = nil
    ) -> URL? {
        let resolved = shape ?? (type == "Episode" ? .landscape : .poster)
        return JellyfinArtwork.url(for: self, serverURL: serverURL, shape: resolved)
    }
}
