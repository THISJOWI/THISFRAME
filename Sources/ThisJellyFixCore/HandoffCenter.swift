import Foundation
import Observation

/// Single owner of "who holds Handoff right now".
///
/// Two `isEligibleForHandoff` activities publishing at once (browsing from
/// the always-mounted Home, playing from the player) makes the system pick
/// one nondeterministically — the Mac Dock advertised `browsing`, whose
/// macOS handler does nothing. While playback is active, browsing yields.
@MainActor
@Observable
public final class HandoffCenter {
    public static let shared = HandoffCenter()

    /// True while a player session owns the Handoff advertisement.
    public private(set) var isPlaybackActive = false

    /// The browsing activity should stay eligible only when nothing is
    /// playing — SwiftUI reads this via observation.
    public var shouldPublishBrowsing: Bool { !isPlaybackActive }

    public init() {}

    public func setPlaybackActive(_ active: Bool) {
        guard active != isPlaybackActive else { return }
        isPlaybackActive = active
        TJFLog("handoff: playbackActive=\(active) browsingYields=\(active)")
    }
}
