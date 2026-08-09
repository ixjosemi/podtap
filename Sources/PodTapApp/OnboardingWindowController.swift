import AppKit
import SwiftUI

/// Hosts the setup flow in a real window.
///
/// SwiftUI's `Window` scene cannot be opened from outside the view hierarchy,
/// and an accessory app has no view on screen at launch — so the window is
/// managed through AppKit instead.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(preferences: Preferences, onFinish: @escaping () -> Void) {
        if let window {
            bringToFront(window)
            return
        }

        let root = OnboardingView(preferences: preferences) { [weak self] in
            onFinish()
            self?.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PodTap Setup"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        bringToFront(window)
    }

    func close() {
        window?.close()
        window = nil
    }

    /// An accessory app is not in the activation chain, so showing a window is
    /// not enough — it also has to ask for focus explicitly.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
