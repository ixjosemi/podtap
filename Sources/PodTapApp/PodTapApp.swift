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

    var body: some Scene {
        MenuBarExtra {
            MenuContent(preferences: preferences)
                .environmentObject(controller)
        } label: {
            Image(systemName: menuBarSymbol)
        }

        Settings {
            SettingsView(preferences: preferences)
                .environmentObject(controller)
        }
    }

    /// El icono comunica el estado de un vistazo: si está grabando, si está
    /// listo, o si los EarPods no están puestos.
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
        Text(controller.isDeviceConnected ? "EarPods conectados" : "EarPods no conectados")

        if controller.isDeviceConnected && preferences.isEnabled {
            Text("Mantén el botón para \(preferences.outputCombination.displayName)")
        }

        Divider()

        Toggle("Activar PodTap", isOn: $preferences.isEnabled)

        SettingsLink {
            Text("Ajustes…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Salir de PodTap") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

/// Existe por un motivo concreto: garantizar que el dispositivo se devuelve al
/// sistema y que ninguna tecla queda bajada al cerrar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var controller: AppController?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.controller?.prepareForTermination()
        }
    }
}
