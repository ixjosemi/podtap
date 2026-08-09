import AppKit
import CoreGraphics
import KeyOutput

/// Captures a shortcut by tapping keyboard events before any other app sees
/// them.
///
/// An `NSEvent` monitor cannot do this job. The Globe/Fn transition never
/// reaches application-level event delivery: measured with listen-only taps at
/// all three locations, a Globe press appears at `.cghidEventTap` and
/// `.cgSessionEventTap` and **never** at `.cgAnnotatedSessionEventTap`, while
/// Control appears at all three. Something between the session tap and the
/// application swallows it, which is why Globe looked unmappable no matter how
/// the monitor was written.
///
/// The tap **consumes** what it captures. Recording ⌘Q must not quit PodTap,
/// and recording Globe must not trigger the very dictation app being mapped.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    /// Echoed back while keys are down, so a modifier-only shortcut visibly
    /// registers instead of looking ignored.
    @Published private(set) var heldCombination = KeyCombination(keyCode: nil)

    /// A tap that swallows the keyboard must never outlive the user's
    /// attention. Escape and clicking the field both cancel, and neither helps
    /// if the window is simply forgotten.
    private static let timeLimit: TimeInterval = 20

    private nonisolated(unsafe) var tap: CFMachPort?
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?
    private var resignObserver: NSObjectProtocol?
    private var recording = ShortcutRecording()
    private var onCommit: ((KeyCombination) -> Void)?

    deinit {
        teardownTap()
    }

    /// Starts capturing. Returns `false` when the tap cannot be created, which
    /// in practice means Accessibility has not been granted.
    @discardableResult
    func start(onCommit: @escaping (KeyCombination) -> Void) -> Bool {
        cancel()

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        self.onCommit = onCommit
        recording = ShortcutRecording()
        heldCombination = recording.heldCombination
        isRecording = true

        watchdog = Timer.scheduledTimer(withTimeInterval: Self.timeLimit, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
        // Switching away mid-recording would leave the keyboard captured for an
        // app the user is no longer looking at.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }

        return true
    }

    func cancel() {
        watchdog?.invalidate()
        watchdog = nil

        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil

        onCommit = nil
        recording = ShortcutRecording()
        heldCombination = recording.heldCombination
        isRecording = false
        teardownTap()
    }

    // MARK: - Event handling

    private static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let recorder = Unmanaged<ShortcutRecorder>.fromOpaque(context).takeUnretainedValue()

        return MainActor.assumeIsolated {
            recorder.shouldSwallow(type: type, event: event)
                ? nil
                : Unmanaged.passUnretained(event)
        }
    }

    private func shouldSwallow(type: CGEventType, event: CGEvent) -> Bool {
        // macOS disables a tap that takes too long to answer, and re-enabling
        // is the only way back. The notice itself must pass through untouched.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        // Still swallowing between committing and the tap actually coming down,
        // so no half-captured keystroke escapes into the frontmost app.
        guard isRecording else { return true }

        // Releases are swallowed too: the press never arrived anywhere, and a
        // lone release leaves whatever app is in front with a key stuck down.
        guard type != .keyUp else { return true }

        let flags = event.flags.rawValue
        let outcome =
            type == .flagsChanged
            ? recording.handle(.modifiersChanged(flags))
            : recording.handle(
                .keyDown(
                    keyCode: UInt16(
                        truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                    modifiers: flags
                )
            )

        switch outcome {
        case .recording: heldCombination = recording.heldCombination
        case .cancelled: finish(with: nil)
        case .committed(let combination): finish(with: combination)
        }

        return true
    }

    /// Ends the recording. Tearing the tap down from inside its own callback is
    /// asking for trouble, so the port is unwound on the next pass of the run
    /// loop and only the observable state changes here.
    private func finish(with combination: KeyCombination?) {
        let commit = onCommit
        onCommit = nil
        isRecording = false

        Task { @MainActor [weak self] in
            self?.cancel()
            if let combination { commit?(combination) }
        }
    }

    private nonisolated func teardownTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }
}
