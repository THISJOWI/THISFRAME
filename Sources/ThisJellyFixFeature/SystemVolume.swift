#if os(iOS)
import AVFoundation
import MediaPlayer
import ThisJellyFixCore
import UIKit

/// Real device volume on iOS.
///
/// `AVPlayer.volume` is only the app-private gain — the edge slider used to
/// move that number while the actual output (volume buttons, Control Center,
/// what you hear) never changed. `MPVolumeView`'s hidden slider is the only
/// public surface that writes the system output, and
/// `AVAudioSession.outputVolume` is the authoritative read (KVO-compliant),
/// so hardware button presses come back through the same channel.
@MainActor
final class SystemVolumeController {
    static let shared = SystemVolumeController()

    /// Last known system output volume (0...1).
    private(set) var value: Double
    /// Fired on every system volume change (slider write OR volume buttons).
    var onChange: ((Double) -> Void)?

    /// Kept alive for the app's lifetime: the slider is read from its
    /// subviews on each write, and a released MPVolumeView stops tracking.
    private let volumeView = MPVolumeView(frame: .zero)
    private var observation: NSKeyValueObservation?

    init() {
        value = Double(AVAudioSession.sharedInstance().outputVolume)
        observation = AVAudioSession.sharedInstance()
            .observe(\.outputVolume, options: [.initial, .new]) { [weak self] _, change in
                guard let raw = change.newValue else { return }
                let next = Double(raw)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.value = next
                    self.onChange?(next)
                }
            }
    }

    /// Write the system volume (0...1 clamped) through the hidden slider.
    /// The KVO observer above delivers the confirmed value back.
    func set(_ newValue: Double) {
        let clamped = min(1, max(0, newValue))
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else {
            TJFLog("systemVolume: MPVolumeView slider not found")
            return
        }
        slider.setValue(Float(clamped), animated: false)
        slider.sendActions(for: .valueChanged)
    }
}
#endif
