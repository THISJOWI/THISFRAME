import SwiftUI
import Observation

/// macOS-only sidebar visibility state for `HomeView`'s `NavigationSplitView`.
///
/// Why this exists: on macOS the player is presented as a ZStack sibling INSIDE
/// the split view's DETAIL column (`.fullScreenCover` is unavailable on macOS),
/// so it can never paint over the sidebar — the video got clipped to the column
/// and the sidebar sat on top of it. Since the window toolbar already hides while
/// playing, the sidebar collapses too: `.detailOnly` while the player is up, then
/// the previous value (usually `.all`, or whatever the user last chose) is
/// restored on dismissal so the sidebar returns exactly as it was.
@Observable
final class SplitViewState {
    static let shared = SplitViewState()

    /// Drives `NavigationSplitView(columnVisibility:)` in `HomeView`.
    var visibility: NavigationSplitViewVisibility = .automatic
    /// Value captured before collapsing, restored when the player dismisses.
    private var previous: NavigationSplitViewVisibility = .automatic

    private init() {}

    func collapseForPlayer() {
        if visibility != .detailOnly {
            previous = visibility
            visibility = .detailOnly
        }
    }

    func restore() {
        visibility = previous
    }
}
