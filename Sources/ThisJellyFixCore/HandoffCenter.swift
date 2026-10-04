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

    /// How many DetailView instances are currently on screen (nested stacks
    /// push/pop without inspecting NavigationPath, which exposes no elements).
    private var detailActiveCount = 0

    /// The browsing activity should stay eligible only when nothing is
    /// playing AND no detail screen is on top — SwiftUI reads this via
    /// observation.
    public var shouldPublishBrowsing: Bool { !isPlaybackActive && detailActiveCount == 0 }

    public init() {}

    public func setPlaybackActive(_ active: Bool) {
        guard active != isPlaybackActive else { return }
        isPlaybackActive = active
        TJFLog("handoff: playbackActive=\(active) browsingYields=\(active)")
    }

    /// Called from DetailView.onAppear/onDisappear. Counted (not a bool):
    /// popping [Item1, Item2] must keep the slot claimed while Item1 is
    /// still under it. Clamped — a spurious disappear can't go negative.
    public func setDetailActive(_ active: Bool) {
        if active {
            detailActiveCount += 1
        } else {
            detailActiveCount = max(0, detailActiveCount - 1)
        }
        TJFLog("handoff: detailActiveCount=\(detailActiveCount) browsingYields=\(shouldPublishBrowsing)")
    }
}
