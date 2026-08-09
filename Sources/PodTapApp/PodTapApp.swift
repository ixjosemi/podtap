import AppKit
import SwiftUI

@main
struct PodTapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @StateObject private var preferences: Preferences
    @StateObject private var controller: AppController

    init() {
        let preferences = Preferences()
        _preferences = StateObject(wrappedValue: preferences)
        _controller = StateObject(wrappedValue: AppController(preferences: preferences))
    }

    /// The menu bar is the only scene. Settings and setup are AppKit windows
    /// owned by the controller, because SwiftUI's `Settings` scene silently
    /// does nothing in an accessory app.
    var body: some Scene {
        // `isInserted` lets the icon be removed entirely without tearing down
        // the app, so PodTap can run as a pure background agent.
        MenuBarExtra(isInserted: menuBarIconInserted) {
            MenuContent(preferences: preferences)
                .environmentObject(controller)
        } label: {
            Image(systemName: menuBarSymbol)
        }
    }

    /// SwiftUI writes back to `isInserted` on every layout pass. Forwarding an
    /// unchanged value would republish `Preferences`, re-render the scene, and
    /// write again — an infinite loop that pins a core. No-op writes are
    /// filtered out here so only genuine user changes propagate.
    private var menuBarIconInserted: Binding<Bool> {
        Binding(
            get: { preferences.showsMenuBarIcon },
            set: { newValue in
                guard newValue != preferences.showsMenuBarIcon else { return }
                preferences.showsMenuBarIcon = newValue
            }
        )
    }

    /// The icon carries the state at a glance: recording, ready, or no EarPods.
    private var menuBarSymbol: String {
        guard preferences.isEnabled else { return "headphones.slash" }
        if controller.isDictating { return "waveform" }
        return controller.isDeviceConnected ? "headphones" : "headphones.slash"
    }
}

private struct MenuContent: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject var preferences: Preferences

    var body: some View {
        Text(controller.isDeviceConnected ? "EarPods connected" : "EarPods not connected")

        if controller.isDeviceConnected && preferences.isEnabled {
            Text(
                controller.isDictating
                    ? "Dictating — press the button to stop"
                    : "Press the button to send \(preferences.outputCombination.displayName)"
            )
        }

        Divider()

        Toggle("Enable PodTap", isOn: $preferences.isEnabled)

        Button("Settings…") { controller.showSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit PodTap") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

/// Exists for two specific reasons: making sure the device is handed back and
/// no key is left held down on quit, and giving a background-only PodTap a way
/// back to its settings.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var controller: AppController?

    /// Relaunching PodTap while it is already running is the only route back
    /// into the app when the menu bar icon is hidden. Spotlight, Raycast and
    /// the Finder all arrive here.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        MainActor.assumeIsolated {
            guard let controller = Self.controller else { return }
            if controller.preferences.hasCompletedSetup {
                controller.showSettings()
            } else {
                controller.showOnboarding()
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.controller?.prepareForTermination()
        }
    }
}
