import Foundation

/// Physical phase of the remote button, as reported by the HID device.
///
/// USB-C EarPods publish the `PlayPause` usage (`0x00CD`) on the Consumer Page
/// (`0x0C`) with genuine 1/0 value transitions. macOS collapses that pair into
/// a single playback toggle further up the stack; working below that layer
/// keeps the press duration intact.
public enum ButtonPhase: Sendable, Equatable {
    case pressed
    case released
}

/// A button event with its monotonic timestamp, in seconds.
///
/// Time is injected rather than read from a global clock so classification is
/// deterministic and testable without hardware.
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
    /// Re-emit play/pause to the system. Required because seizing the device
    /// means the original event no longer reaches anyone.
    case emitPlayPause
    /// Press the configured key and hold it down.
    case beginDictation
    /// Release the configured key.
    case endDictation
}

/// Observable state of the classifier. Public so the menu bar can reflect it
/// and so tests can assert on it.
public enum ClassifierState: Sendable, Equatable {
    /// Button up, nothing in flight.
    case idle
    /// Button down since `since`, hold threshold not yet crossed.
    case pressing(since: TimeInterval)
    /// Threshold crossed: the key is held down and dictation is running.
    case dictating
}

/// Translates physical button presses into intents, applying the policy
/// "short tap means play/pause, press and hold means dictation".
///
/// A dependency-free `struct`: the same value can be replayed in a test by
/// feeding it a sequence of events and ticks.
public struct GestureClassifier: Sendable {
    /// How many seconds a press must last before it stops being a tap.
    ///
    /// Measured on real hardware: user taps land between 79 and 231 ms, while
    /// a deliberate hold runs past 1700 ms.
    public var holdThreshold: TimeInterval

    public private(set) var state: ClassifierState

    public init(holdThreshold: TimeInterval = 0.3, state: ClassifierState = .idle) {
        self.holdThreshold = holdThreshold
        self.state = state
    }

    /// Processes a button transition and returns the resulting intents.
    ///
    /// Press duration — not internal state — is the source of truth on release.
    /// If the tick meant to mark the threshold crossing never arrived (busy
    /// process, lazy clock), a long press is still recognised as a hold instead
    /// of degrading into a spurious play/pause.
    public mutating func handle(_ event: ButtonEvent) -> [GestureIntent] {
        switch (state, event.phase) {
        case (.idle, .pressed):
            state = .pressing(since: event.timestamp)
            return []

        // Repeated press without a release: device chatter. Restarting the
        // timer would stop a hold from ever firing.
        case (.pressing, .pressed), (.dictating, .pressed):
            return []

        // Release with no press on record: the app may have started while the
        // button was already down.
        case (.idle, .released):
            return []

        case (.dictating, .released):
            state = .idle
            return [.endDictation]

        case (.pressing(let since), .released):
            state = .idle
            let heldFor = event.timestamp - since
            return heldFor < holdThreshold ? [.emitPlayPause] : []
        }
    }

    /// Clock advance. The classifier cannot notice on its own that a press has
    /// become a hold — no HID event arrives at the threshold — so the input
    /// layer drives it.
    ///
    /// Firing here rather than on release is what makes push-to-talk real:
    /// dictation starts while the button is still held.
    public mutating func tick(at now: TimeInterval) -> [GestureIntent] {
        guard case .pressing(let since) = state else { return [] }
        guard now - since >= holdThreshold else { return [] }

        state = .dictating
        return [.beginDictation]
    }

    /// Aborts any gesture in flight without producing spurious side effects.
    ///
    /// Called when the EarPods are unplugged or the system sleeps. An open
    /// dictation must be closed: otherwise the key stays down forever and the
    /// dictation app records without end.
    public mutating func interrupt() -> [GestureIntent] {
        defer { state = .idle }
        return state == .dictating ? [.endDictation] : []
    }
}
