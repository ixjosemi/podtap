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
    /// Whether the EarPods are genuinely seized. Doubles as the only reliable
    /// proof that Input Monitoring is in effect — see `EarPodsButtonMonitor`.
    @Published private(set) var isReadingDevice = false
    /// Human-readable failure, or `nil` when everything is fine.
    @Published private(set) var failureMessage: String?

    let preferences: Preferences

    private let monitor = EarPodsButtonMonitor()
    private let emitter = KeyEmitter()
    private let onboardingWindow = HostedWindowController()
    private let settingsWindow = HostedWindowController()
    private var classifier = GestureClassifier()
    private var cancellables = Set<AnyCancellable>()

    init(preferences: Preferences) {
        self.preferences = preferences

        monitor.onButton = { [weak self] transition, timestamp in
            self?.handleButton(transition, at: timestamp)
        }
        monitor.onConnectionChange = { [weak self] connected in
            self?.handleConnectionChange(connected)
        }

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
        // Attempted even before setup, and even when it is bound to fail: that
        // failed access attempt is what registers PodTap in the Input
        // Monitoring list. Without it the user has to add the app by hand from
        // the "+" button, which is exactly the friction setup exists to remove.
        start()

        if !preferences.hasCompletedSetup {
            showOnboarding()
        }
    }

    func showOnboarding() {
        onboardingWindow.show(title: "PodTap Setup") {
            OnboardingView(preferences: preferences) { [weak self] in
                self?.onboardingWindow.close()
                self?.start()
            }
            .environmentObject(self)
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
        isReadingDevice = monitor.isReadingDevice
    }

    func stop() {
        abortGesture()
        monitor.stop()
        isDeviceConnected = false
        isReadingDevice = false
    }

    /// Quits and reopens PodTap.
    ///
    /// The only cure for a stale Input Monitoring answer: the HID layer caches
    /// it for the lifetime of the process, so a permission granted while PodTap
    /// was running is invisible until a fresh one starts. The device is handed
    /// back first, or the incoming instance would find it already seized.
    func relaunch() {
        prepareForTermination()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration
        ) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Opens settings. Reachable from the menu bar, and — crucially — from
    /// relaunching the app, which is the only way back in when the menu bar
    /// icon is hidden.
    func showSettings() {
        settingsWindow.show(title: "PodTap Settings") {
            SettingsView(preferences: preferences).environmentObject(self)
        }
    }

    /// Hands the device back and releases any held key. Must run before the
    /// process exits, or the system could be left with the key down.
    func prepareForTermination() {
        stop()
    }

    // MARK: - Events

    private func handleButton(_ transition: ButtonTransition, at timestamp: TimeInterval) {
        apply(
            classifier.handle(
                ButtonEvent(
                    phase: transition == .pressed ? .pressed : .released,
                    timestamp: timestamp
                )
            )
        )
    }

    private func handleConnectionChange(_ connected: Bool) {
        isDeviceConnected = connected
        isReadingDevice = monitor.isReadingDevice
        // Unplugging mid-press would otherwise leave the key down forever, and
        // the dictation app recording with no way to stop.
        if !connected { abortGesture() }
    }

    private func abortGesture() {
        apply(classifier.interrupt())
    }

    private func apply(_ intents: [GestureIntent]) {
        for intent in intents {
            switch intent {
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
