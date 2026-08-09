import AppKit
import CoreGraphics
import Foundation

/// Synthesises the events PodTap must produce on the system.
///
/// Two very different paths live here:
///
/// - The **configurable key** uses `CGEvent`, public and stable API.
/// - **Play/pause** has no public equivalent. Seizing the HID device means the
///   original event stops existing, so it has to be rebuilt by hand with an
///   `NSEvent.systemDefined` carrying the magic values macOS expects. This is
///   the project's only undocumented dependency, deliberately confined to this
///   one file.
public final class KeyEmitter {
    /// `NX_KEYTYPE_PLAY`, from IOKit/hidsystem/ev_keymap.h.
    private static let mediaKeyPlay: Int32 = 16

    private let eventSource: CGEventSource?

    public init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    /// Presses the configured key and leaves it held down.
    public func pressDown(_ combination: KeyCombination) {
        postKey(combination, keyDown: true)
    }

    /// Releases the configured key.
    public func releaseUp(_ combination: KeyCombination) {
        postKey(combination, keyDown: false)
    }

    private func postKey(_ combination: KeyCombination, keyDown: Bool) {
        guard
            let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(combination.keyCode),
                keyDown: keyDown
            )
        else { return }

        event.flags = combination.flags
        event.post(tap: .cghidEventTap)
    }

    /// Re-emits a full play/pause press and release to the system.
    public func tapPlayPause() {
        postMediaKey(down: true)
        postMediaKey(down: false)
    }

    private func postMediaKey(down: Bool) {
        // The 0xA00/0xB00 flags and the data1 bitfield are undocumented: they
        // are the de facto contract every macOS media-key app relies on. If
        // Apple changes them, play/pause passthrough breaks — button capture
        // does not.
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let state: Int = down ? 0xA : 0xB
        let data1 = Int((Self.mediaKeyPlay << 16) | Int32(state << 8))

        guard
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
        else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
