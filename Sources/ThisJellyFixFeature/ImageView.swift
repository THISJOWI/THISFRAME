import SwiftUI
import ThisJellyFixCore

// MARK: - Image Cache

/// Thread-safe image cache using NSCache. Stores decoded images in memory
/// so scrolling through lists doesn't re-fetch from network.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, PlatformImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func image(for url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: PlatformImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

#if os(macOS)
typealias PlatformImage = NSImage
extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: size),
             from: NSRect(origin: .zero, size: self.size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
#else
typealias PlatformImage = UIImage
#endif

// MARK: - Cached Async Image Loader

@MainActor
private final class CachedImageLoader: ObservableObject {
    @Published var image: PlatformImage?
    @Published var isLoading = false

    private var currentURL: URL?
    /// Portrait poster to fall back to when the preferred (wide) frame fails:
    /// a failed Thumb/Backdrop fetch used to leave a dead dark card.
    private var fallbackURL: URL?
    private var triedFallbackFor: URL?

    func load(url: URL, fallback: URL? = nil) {
        if let fallback { fallbackURL = fallback }
        // Return cached image immediately
        if let cached = ImageCache.shared.image(for: url) {
            self.image = cached
            return
        }

        guard currentURL != url else { return }
        currentURL = url
        isLoading = true

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200

                // A 4xx/5xx body decodes to nothing — without the status check
                // we used to treat "error JSON" as a broken image and give up.
                guard (200..<300).contains(status),
                      let downloaded = PlatformImage(data: data) else {
                    await self.retryWithFallback(url: url)
                    return
                }

                // Cache the decoded image
                ImageCache.shared.setImage(downloaded, for: url)

                // Only update if this is still the current request
                if self.currentURL == url {
                    self.image = downloaded
                    self.isLoading = false
                }
            } catch {
                await self.retryWithFallback(url: url)
            }
        }
    }

    /// One retry with the portrait poster when the preferred frame is missing
    /// or unreadable; otherwise settle on the placeholder (never spin forever).
    private func retryWithFallback(url: URL) async {
        guard let fallback = fallbackURL,
              fallback != url,
              triedFallbackFor != url,
              currentURL == url
        else {
            isLoading = false
            return
        }
        TJFLog("image: fallback \(url.lastPathComponent) → \(fallback.lastPathComponent)")
        triedFallbackFor = url
        currentURL = nil
        load(url: fallback)
    }

    func cancel() {
        currentURL = nil
    }
}

// MARK: - MareaImageView

/// The app's only image renderer.
///
/// Three sizing modes, and the artwork can never escape the box it was
/// given:
/// - **fixed** — an exact `width` × `height` box (cards with a designed
///   size). The picture is cropped to fill it, never stretched.
/// - **ratio** — the box keeps `aspectRatio` and takes the width its
///   container offers. This is what cards in adaptive grids use: the
///   artwork can never be wider than the column that hosts it.
/// - **flexible** — fills whatever frame the caller gives (the detail hero,
///   the "continue watching" card). The caller owns the bounds.
struct MareaImageView: View {
    let url: URL?
    let placeholder: String
    /// Fixed box width. Zero together with a zero height means "flexible".
    let width: CGFloat
    /// Fixed box height. Zero together with a zero width means "flexible".
    let height: CGFloat
    /// When set, the box keeps this width/height ratio and takes the width
    /// its container offers. Overrides the fixed box.
    var aspectRatio: CGFloat? = nil
    /// Tried once when `url` fails (missing Thumb/Backdrop frame) so the card
    /// shows the portrait poster instead of a dead dark rectangle.
    var fallbackURL: URL? = nil

    @StateObject private var loader = CachedImageLoader()

    init(
        url: URL?,
        placeholder: String = "?",
        width: CGFloat = 150,
        height: CGFloat = 220,
        aspectRatio: CGFloat? = nil,
        fallbackURL: URL? = nil
    ) {
        self.url = url
        self.placeholder = placeholder
        self.width = width
        self.height = height
        self.aspectRatio = aspectRatio
        self.fallbackURL = fallbackURL
    }

    /// True when the view takes the bounds of its container instead of a
    /// fixed box.
    var isFlexible: Bool { width <= 0 && height <= 0 && aspectRatio == nil }

    var body: some View {
        Group {
            if let image = loader.image {
                artwork(image)
                    .transition(.opacity)
            } else if loader.isLoading {
                ProgressView()
                    .mareaRatioBox(aspectRatio, contentMode: .fit)
                    .transition(.opacity)
            } else {
                placeholderBox
                    .transition(.opacity)
            }
        }
        .modifier(MareaImageSizing(width: width, height: height, aspectRatio: aspectRatio))
        // The picture fades in over the placeholder instead of jumping in.
        // The animation is keyed on "is there an image", not on the image
        // itself: it runs once per picture, never while scrolling.
        .mareaAnimation(MareaMotion.fade, value: loader.image != nil)
        .task(id: url) {
            if let url {
                loader.load(url: url, fallback: fallbackURL)
            }
        }
    }

    /// The loaded picture. Cropped to fill its box — never stretched, never
    /// allowed to grow past it.
    @ViewBuilder
    private func artwork(_ image: PlatformImage) -> some View {
        #if os(macOS)
        Image(nsImage: image)
            .resizable()
            .mareaRatioBox(aspectRatio, contentMode: .fill)
        #else
        Image(uiImage: image)
            .resizable()
            .mareaRatioBox(aspectRatio, contentMode: .fill)
        #endif
    }

    private var placeholderBox: some View {
        ZStack {
            MareaTheme.Colors.surface
            Text(placeholder)
                .font(.title2.bold())
                .foregroundStyle(MareaTheme.Colors.accent.opacity(0.6))
        }
        .mareaRatioBox(aspectRatio, contentMode: .fit)
    }
}

/// Applies a fixed aspect ratio when there is one, and leaves the view
/// alone when there is not.
private extension View {
    func mareaRatioBox(_ ratio: CGFloat?, contentMode: ContentMode) -> some View {
        if let ratio {
            return AnyView(self.aspectRatio(ratio, contentMode: contentMode))
        }
        return AnyView(self)
    }
}

/// Fixed tile (frame + rounded corners) for cards, a ratio box that follows
/// the container width, or fill-the-frame with no corner rounding when the
/// caller passes 0/0.
private struct MareaImageSizing: ViewModifier {
    let width: CGFloat
    let height: CGFloat
    let aspectRatio: CGFloat?

    private var isFlexible: Bool { width <= 0 && height <= 0 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let aspectRatio {
            // The branches already keep the ratio; this only makes the box
            // take the width the container offers.
            content
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
        } else if isFlexible {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Rectangle())
        } else {
            content
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: MareaTheme.Radius.card))
        }
    }
}
