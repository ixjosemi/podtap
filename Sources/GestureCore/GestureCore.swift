import Foundation

/// Physical phase of the remote button, as reported by the HID device.
///
/// USB-C EarPods publish the `PlayPause` usage (`0x00CD`) on the Consumer Page
/// (`0x0C`) with genuine 1/0 value transitions. macOS collapses that pair into
/// a single playback toggle further up the stack; working below that layer is
/// what makes the button available for something else entirely.
public enum ButtonPhase: Sendable, Equatable {
    case pressed
    case released
}

/// A button event with its monotonic timestamp, in seconds.
///
/// Nothing here measures durations any more, but the timestamp is kept: it
/// costs nothing, it is what the HID layer already has, and it is the first
/// thing any future gesture would need.
public struct ButtonEvent: Sendable, Equatable {
    public let phase: ButtonPhase
    public let timestamp: TimeInterval

    public init(phase: ButtonPhase, timestamp: TimeInterval) {
        self.phase = phase
        self.timestamp = timestamp
    }
}

/// What the app should make happen. Deliberately abstract: this module knows
/// nothing about `CGEvent` or which key the user configured.
public enum GestureIntent: Sendable, Equatable {
    /// Press the configured key and leave it down.
    case beginDictation
    /// Release the configured key.
    case endDictation
}

/// Observable state of the classifier. Public so the menu bar can reflect it
/// and so tests can assert on it.
///
/// The button's own position is part of the state rather than a separate flag,
/// because the only thing that can go wrong here is mistaking device chatter —
/// two presses with no release between them — for a second gesture.
public enum ClassifierState: Sendable, Equatable {
    /// Nothing running, button up.
    case idle
    /// Dictation just started and the button is still down.
    case opening
    /// Dictation running with the button free. This is the state that matters:
    /// it is the only one in which the microphone works.
    case dictating
    /// Dictation just ended and the button is still down.
    case closing
}

/// Turns presses of the remote button into a dictation on/off toggle.
///
/// ### Why a toggle, and why the key latches
///
/// USB-C EarPods mute their own microphone for as long as the remote button is
/// held. Measured over two seconds of continuous speech with the button down:
/// 88 200 consecutive samples, every one exactly zero, against a normal signal
/// either side. The button is read through the microphone line — the same
/// resistor trick the analogue remote uses — so holding it is literally
/// silencing the capsule.
///
/// Anything that asks the user to keep the button down therefore records
/// silence. One press starts, the button is released, and the key stays down on
/// its own until a second press. To the dictation app it looks like an ordinary
/// key held for the whole utterance, so no toggle mode is needed at the other
/// end.
///
/// Play/pause is gone by choice, not by accident: the device is seized, the
/// press is never forwarded, and the button belongs to dictation alone.
///
/// A dependency-free `struct`: the same value can be replayed in a test by
/// feeding it a sequence of events.
public struct GestureClassifier: Sendable {
    public private(set) var state: ClassifierState

    public init(state: ClassifierState = .idle) {
        self.state = state
    }

    /// Processes a button transition and returns the resulting intents.
    public mutating func handle(_ event: ButtonEvent) -> [GestureIntent] {
        switch (state, event.phase) {
        case (.idle, .pressed):
            state = .opening
            return [.beginDictation]

        case (.dictating, .pressed):
            state = .closing
            return [.endDictation]

        // Repeated press with no release in between: device chatter. Acting on
        // it would start and immediately stop, leaving the button looking dead.
        case (.opening, .pressed), (.closing, .pressed):
            return []

        // Letting go of the opening press is what brings the microphone back.
        // It ends nothing — that is the entire point of the latch.
        case (.opening, .released):
            state = .dictating
            return []

        case (.closing, .released):
            state = .idle
            return []

        // Release with no press on record: the app may have started while the
        // button was already down.
        case (.idle, .released), (.dictating, .released):
            return []
        }
    }

    /// Aborts any gesture in flight without producing spurious side effects.
    ///
    /// Called when the EarPods are unplugged or the system sleeps. Because the
    /// latch outlives the button, this is the only thing standing between an
    /// interrupted dictation and a key left held down forever.
    public mutating func interrupt() -> [GestureIntent] {
        defer { state = .idle }

        switch state {
        case .opening, .dictating: return [.endDictation]
        // The key is already up in `.closing`, and releasing it twice would
        // leave the dictation app with an unmatched key-up.
        case .idle, .closing: return []
        }
    }
}
