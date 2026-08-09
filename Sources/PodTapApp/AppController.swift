import AppKit
import Combine
import Foundation
import GestureCore
import HIDInput
import KeyOutput

/// Wires button capture, gesture classification and event synthesis together,
/// and exposes observable state to the interface.
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var isDeviceConnected = false
    @Published private(set) var isDictating = false
    /// Human-readable failure, or `nil` when everything is fine.
    @Published private(set) var failureMessage: String?

    let preferences: Preferences

    private let monitor = EarPodsButtonMonitor()
    private let emitter = KeyEmitter()
    private let onboarding = OnboardingWindowController()
    private var classifier = GestureClassifier()
    /// One-shot timer armed when a press starts: it is what turns "still held"
    /// into an event, since the hardware sends nothing at the threshold.
    private var holdTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(preferences: Preferences) {
        self.preferences = preferences
        classifier.holdThreshold = preferences.holdThreshold

        monitor.onButton = { [weak self] transition, timestamp in
            self?.handleButton(transition, at: timestamp)
        }
        monitor.onConnectionChange = { [weak self] connected in
            self?.handleConnectionChange(connected)
        }

        preferences.$holdThreshold
            .sink { [weak self] threshold in self?.classifier.holdThreshold = threshold }
            .store(in: &cancellables)

        // `dropFirst` avoids acting on the initial value: start-up happens once,
        // below, outside `init`.
        preferences.$isEnabled
            .dropFirst()
            .sink { [weak self] enabled in enabled ? self?.start() : self?.stop() }
            .store(in: &cancellables)

        AppDelegate.controller = self

        // Deferred to the next run loop pass: starting inside `init` would mean
        // using `self` before it finishes being constructed.
        Task { @MainActor [weak self] in self?.launch() }
    }

    // MARK: - Lifecycle

    /// Entry point at app launch. New users get the setup flow; everyone else
    /// goes straight to listening.
    func launch() {
        if preferences.hasCompletedSetup {
            start()
        } else {
            showOnboarding()
        }
    }

    func showOnboarding() {
        onboarding.show(preferences: preferences) { [weak self] in
            self?.start()
        }
    }

    func start() {
        guard preferences.isEnabled else { return }
        do {
            try monitor.start()
            failureMessage = nil
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    func stop() {
        abortGesture()
        monitor.stop()
        isDeviceConnected = false
    }

    /// Opens the settings window even though the app has no menu of its own
    /// when the menu bar icon is hidden.
    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Hands the device back and releases any held key. Must run before the
    /// process exits, or the system could be left with the key down.
    func prepareForTermination() {
        stop()
    }

    // MARK: - Events

    private func handleButton(_ transition: ButtonTransition, at timestamp: TimeInterval) {
        let event = ButtonEvent(
            phase: transition == .pressed ? .pressed : .released,
            timestamp: timestamp
        )

        switch transition {
        case .pressed: scheduleHoldTimer()
        case .released: cancelHoldTimer()
        }

        apply(classifier.handle(event))
    }

    private func handleConnectionChange(_ connected: Bool) {
        isDeviceConnected = connected
        // Unplugging mid-press would otherwise leave the key down forever, and
        // the dictation app recording with no way to stop.
        if !connected { abortGesture() }
    }

    private func abortGesture() {
        cancelHoldTimer()
        apply(classifier.interrupt())
    }

    private func scheduleHoldTimer() {
        cancelHoldTimer()
        holdTimer = Timer.scheduledTimer(
            withTimeInterval: preferences.holdThreshold,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.classifier.tick(at: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func apply(_ intents: [GestureIntent]) {
        for intent in intents {
            switch intent {
            case .emitPlayPause:
                emitter.tapPlayPause()
            case .beginDictation:
                emitter.pressDown(preferences.outputCombination)
                isDictating = true
            case .endDictation:
                emitter.releaseUp(preferences.outputCombination)
                isDictating = false
            }
        }
    }
}
