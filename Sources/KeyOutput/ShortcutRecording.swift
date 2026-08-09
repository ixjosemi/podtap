import CoreGraphics
import Foundation

/// Turns a stream of keyboard events into a `KeyCombination`.
///
/// Pure and clock-free, in the same spirit as `GestureCore`: the awkward part
/// of recording a shortcut is that modifiers arrive and leave **one at a
/// time**, and that is worth testing without a keyboard in the loop.
public struct ShortcutRecording: Sendable {
    public enum Event: Sendable, Equatable {
        /// The complete set of modifiers currently down, as macOS reports it on
        /// every transition.
        case modifiersChanged(UInt64)
        case keyDown(keyCode: UInt16, modifiers: UInt64)
    }

    public enum Outcome: Sendable, Equatable {
        /// Nothing decided yet — the user may still be adding keys.
        case recording
        case cancelled
        case committed(KeyCombination)
    }

    /// kVK_Escape.
    private static let escape: UInt16 = 53

    /// Every modifier seen during the current press, rather than the ones still
    /// down. Releasing ⌘⇧ reports `⌘` before it reports nothing, so trusting the
    /// last non-zero report would record half the combination.
    private var heldModifiers: UInt64 = 0

    public init() {}

    /// What is held right now, for echoing back to the user mid-recording.
    public var heldCombination: KeyCombination {
        KeyCombination(keyCode: nil, modifierFlags: heldModifiers)
    }

    public mutating func handle(_ event: Event) -> Outcome {
        switch event {
        case .modifiersChanged(let current):
            return handleModifiers(current)
        case .keyDown(let keyCode, let modifiers):
            return handleKey(keyCode: keyCode, modifiers: modifiers)
        }
    }

    private mutating func handleModifiers(_ current: UInt64) -> Outcome {
        let supported = current & KeyCombination.supportedModifiers

        guard supported == 0 else {
            heldModifiers |= supported
            return .recording
        }

        // Everything released: whatever passed through is the shortcut.
        guard heldModifiers != 0 else { return .recording }

        let recorded = KeyCombination(keyCode: nil, modifierFlags: heldModifiers)
        heldModifiers = 0
        return .committed(recorded)
    }

    private mutating func handleKey(keyCode: UInt16, modifiers: UInt64) -> Outcome {
        // Escape on its own cancels, which is what everyone expects. Held with
        // modifiers it is a legitimate shortcut, so it is recorded.
        if keyCode == Self.escape && modifiers & KeyCombination.supportedModifiers == 0 {
            heldModifiers = 0
            return .cancelled
        }

        heldModifiers = 0
        return .committed(
            KeyCombination(keyCode: keyCode, modifierFlags: modifiers & ~Self.globe)
        )
    }

    /// Dropped from key combinations because macOS sets it on arrow, page and
    /// function keys of its own accord. A key arriving with the Fn flag cannot
    /// be told apart from one pressed while Globe was held, and recording ← as
    /// 🌐← would be wrong far more often than right. Globe on its own is
    /// unaffected: it travels as a modifier-only combination.
    private static let globe = CGEventFlags.maskSecondaryFn.rawValue
}
