import Foundation

/// Player transport jump sizes, in seconds.
///
/// Persisted in `UserDefaults` (the same store `@AppStorage` writes to) so the
/// player picks a change up live — the transport row reads it on every render.
/// Values are constrained to the set the SF Symbols `gobackward.*` /
/// `goforward.*` family ships, so the icon always matches the jump distance.
public struct PlaybackJumpSettings: Sendable, Equatable {
    public enum Key {
        public static let backward = "player.jump.backward"
        public static let forward = "player.jump.forward"
    }

    /// Selectable distances. Every value has a matching SF Symbol
    /// (`gobackward.10` … `goforward.90`).
    public static let allowedSeconds: [Int] = [10, 15, 30, 60, 90]

    public static let defaultBackward = 15
    public static let defaultForward = 30

    public var backwardSeconds: Int
    public var forwardSeconds: Int

    public init(
        backwardSeconds: Int = PlaybackJumpSettings.defaultBackward,
        forwardSeconds: Int = PlaybackJumpSettings.defaultForward
    ) {
        self.backwardSeconds = PlaybackJumpSettings.validated(backwardSeconds)
        self.forwardSeconds = PlaybackJumpSettings.validated(forwardSeconds)
    }

    /// A stored value may be missing (fresh install) or stale (an option was
    /// removed in a later version). Never hand the transport an arbitrary
    /// number: fall back to the default instead of rendering a missing symbol.
    public static func validated(
        _ seconds: Int,
        fallback: Int = PlaybackJumpSettings.defaultBackward
    ) -> Int {
        allowedSeconds.contains(seconds) ? seconds : fallback
    }

    public static func current(_ defaults: UserDefaults = .standard) -> PlaybackJumpSettings {
        let backward = defaults.object(forKey: Key.backward) as? Int
        let forward = defaults.object(forKey: Key.forward) as? Int
        return PlaybackJumpSettings(
            backwardSeconds: validated(backward ?? defaultBackward),
            forwardSeconds: validated(forward ?? defaultForward, fallback: defaultForward)
        )
    }
}
