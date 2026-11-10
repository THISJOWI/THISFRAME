import Foundation

/// Transport intent for the play/pause glyph.
///
/// The glyph must follow what the USER asked for, never the momentary state
/// of the engine or of a remote receiver: `isPlaying` reads false during
/// every network wait, so deriving the icon from it flickers between PLAY
/// and PAUSE while a video buffers.
///
/// The latch solves the receiver case. The user taps pause; the receiver
/// reports "still playing" for a moment before it applies the command. A
/// naive mirror of the receiver state flips the glyph back to PAUSE (showing
/// that it is playing) while the user is trying to pause it — the exact
/// flicker the local path already avoids by keeping the intent.
///
/// While a local command is pending the intent wins. The pending flag is
/// cleared as soon as the receiver agrees with it; after that the receiver
/// is authoritative again (the user may pause from the Chromecast itself).
public struct TransportIntentLatch: Equatable, Sendable {
    /// What the user last asked for: true = paused.
    public private(set) var isPaused: Bool
    /// True while the receiver has not yet confirmed the local command.
    public private(set) var hasPendingCommand: Bool

    public init(isPaused: Bool = true) {
        self.isPaused = isPaused
        self.hasPendingCommand = false
    }

    /// The user acted on the transport (or playback started).
    public mutating func setLocalIntent(paused: Bool) {
        isPaused = paused
        hasPendingCommand = true
    }

    /// The receiver reported a state (nil = unknown).
    ///
    /// - Returns: the intent to render (`true` = the glyph must offer PLAY).
    public mutating func apply(receiverPlaying: Bool?) -> Bool {
        guard let receiverPlaying else { return isPaused }
        if hasPendingCommand {
            // The receiver confirms the command when its state matches what
            // was asked for. Until then the intent wins.
            if receiverPlaying == !isPaused {
                hasPendingCommand = false
            }
            return isPaused
        }
        // No command in flight: the receiver is authoritative (the user may
        // have paused from the Chromecast itself).
        isPaused = !receiverPlaying
        return isPaused
    }
}
