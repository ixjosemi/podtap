import CoreGraphics
import Foundation

/// Synthesises the events PodTap must produce on the system.
///
/// Two paths live here, and they are genuinely different:
///
/// - A **key with modifiers** is an ordinary `CGEvent` keyboard event.
/// - A **modifiers-only combination** (`⌃⇧`, or Globe on its own) never
///   produces a key event at all. It has to be emitted as a sequence of
///   modifier transitions, one per key, exactly as a human pressing them would
///   generate.
///
/// There used to be a third: re-emitting play/pause, which has no public
/// equivalent and needed an `NSEvent.systemDefined` carrying undocumented magic
/// values. The button no longer forwards play/pause, so that dependency is gone
/// and everything here is public API.
public final class KeyEmitter {
    private let eventSource: CGEventSource?

    public init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    /// Presses the configured combination and leaves it held down.
    public func pressDown(_ combination: KeyCombination) {
        guard !combination.isEmpty else { return }

        if let keyCode = combination.keyCode {
            // Modifiers ride along on the key event itself, which is how a real
            // keyboard reports a shortcut like ⌘S.
            postKey(keyCode: keyCode, flags: combination.flags, keyDown: true)
        } else {
            pressModifiers(combination.flags)
        }
    }

    /// Releases the configured combination.
    public func releaseUp(_ combination: KeyCombination) {
        guard !combination.isEmpty else { return }

        if let keyCode = combination.keyCode {
            postKey(keyCode: keyCode, flags: combination.flags, keyDown: false)
        } else {
            releaseModifiers(combination.flags)
        }
    }

    // MARK: - Keys

    private func postKey(keyCode: UInt16, flags: CGEventFlags, keyDown: Bool) {
        guard
            let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(keyCode),
                keyDown: keyDown
            )
        else { return }

        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Modifier-only combinations

    /// Presses each modifier in turn, accumulating flags as it goes, so a
    /// listener sees the same progression a human hand would produce.
    private func pressModifiers(_ flags: CGEventFlags) {
        var accumulated = CGEventFlags(rawValue: 0)

        for modifier in KeyCombination.modifierKeyCodes where flags.contains(modifier.flag) {
            accumulated.insert(modifier.flag)
            postModifierTransition(keyCode: modifier.keyCode, flags: accumulated)
        }
    }

    /// Releases in reverse order, clearing one flag at a time, ending at zero.
    private func releaseModifiers(_ flags: CGEventFlags) {
        var remaining = flags

        for modifier in KeyCombination.modifierKeyCodes.reversed()
        where flags.contains(modifier.flag) {
            remaining.remove(modifier.flag)
            postModifierTransition(keyCode: modifier.keyCode, flags: remaining)
        }
    }

    /// A modifier transition is a keyboard event retyped as `flagsChanged`,
    /// carrying the key code of the modifier that moved and the resulting flag
    /// state. Posting it as a normal key event produces nothing any app
    /// recognises.
    private func postModifierTransition(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard
            let event = CGEvent(
                keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true)
        else { return }

        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}
