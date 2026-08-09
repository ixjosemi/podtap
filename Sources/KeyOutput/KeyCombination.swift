import CoreGraphics
import Foundation

/// A key combination that PodTap holds down while the user holds the remote
/// button.
///
/// The key itself is optional. Modifier-only shortcuts are first-class here —
/// `⌃⇧` or the Globe key on its own are perfectly ordinary triggers for
/// dictation apps, and none of them ever produce a key event: macOS reports
/// them purely as modifier transitions.
///
/// The key is stored as a virtual key code rather than a character, so the
/// mapping survives keyboard layout changes.
public struct KeyCombination: Sendable, Equatable, Codable {
    /// `nil` when the combination is modifiers only.
    public var keyCode: UInt16?
    /// Raw subset of `CGEventFlags`. Only modifiers a user can actually press
    /// are kept.
    public var modifierFlags: UInt64

    public init(keyCode: UInt16?, modifierFlags: UInt64 = 0) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags & Self.supportedModifiers
    }

    /// F13: a real key macOS leaves unused and no app claims. A good starting
    /// point precisely because it collides with nothing.
    public static let defaultCombination = KeyCombination(keyCode: 105)

    /// The Globe / Fn key on its own, which several dictation apps use.
    public static let globeOnly = KeyCombination(
        keyCode: nil, modifierFlags: CGEventFlags.maskSecondaryFn.rawValue)

    /// Fn is included: it is a modifier like any other as far as the event
    /// system is concerned. Caps Lock is not — it latches, so it cannot be
    /// held.
    static let supportedModifiers: UInt64 =
        CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskSecondaryFn.rawValue

    public var flags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlags)
    }

    /// True when there is nothing to send.
    public var isEmpty: Bool {
        keyCode == nil && modifierFlags == 0
    }

    /// True when the combination is carried entirely by modifier keys.
    public var isModifiersOnly: Bool {
        keyCode == nil && modifierFlags != 0
    }

    /// Display form for the interface, using the usual macOS symbols. Globe
    /// leads, then the canonical ⌃⌥⇧⌘ order.
    public var displayName: String {
        guard !isEmpty else { return "None" }

        var symbols = ""
        if modifierFlags & CGEventFlags.maskSecondaryFn.rawValue != 0 { symbols += "🌐" }
        if modifierFlags & CGEventFlags.maskControl.rawValue != 0 { symbols += "⌃" }
        if modifierFlags & CGEventFlags.maskAlternate.rawValue != 0 { symbols += "⌥" }
        if modifierFlags & CGEventFlags.maskShift.rawValue != 0 { symbols += "⇧" }
        if modifierFlags & CGEventFlags.maskCommand.rawValue != 0 { symbols += "⌘" }

        guard let keyCode else { return symbols }
        return symbols + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// macOS virtual key names. Covers what anyone would pick as a global
    /// shortcut; anything else falls back to its numeric code.
    static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 114: "Help",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]

    /// Virtual key codes for the modifier keys themselves, in the order macOS
    /// reports them when a human presses a combination.
    ///
    /// Needed because a modifier transition carries the key code of the
    /// specific modifier that moved, so emitting `⌃⇧` faithfully means sending
    /// two separate events rather than one with both flags.
    static let modifierKeyCodes: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskSecondaryFn, 0x3F),  // kVK_Function
        (.maskControl, 0x3B),  // kVK_Control
        (.maskAlternate, 0x3A),  // kVK_Option
        (.maskShift, 0x38),  // kVK_Shift
        (.maskCommand, 0x37),  // kVK_Command
    ]
}
