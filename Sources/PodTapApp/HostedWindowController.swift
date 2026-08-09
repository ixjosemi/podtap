import AppKit
import SwiftUI

/// Hosts a SwiftUI view in a real AppKit window.
///
/// SwiftUI's `Settings` scene does not work in an accessory app. Asking for it
/// reports success — `sendAction(showSettingsWindow:)` returns `true` — and no
/// window is ever created, which is worse than an outright failure because
/// nothing looks wrong. Owning the window directly is the only reliable route,
/// and the setup flow already needed exactly this, so both share one mechanism.
@MainActor
final class HostedWindowController {
    private var window: NSWindow?

    /// Shows the window, creating it on first use and reusing it afterwards.
    func show(title: String, content: () -> some View) {
        if let window {
            bringToFront(window)
            return
        }

        let hostingView = NSHostingView(rootView: content())

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        // Closing must not deallocate it: the window is reopened on demand and
        // a released one would crash on the second visit.
        window.isReleasedWhenClosed = false
        window.setContentSize(hostingView.fittingSize)
        window.center()

        self.window = window
        bringToFront(window)
    }

    func close() {
        window?.close()
    }

    /// An accessory app is not in the activation chain, so ordering a window
    /// front is not enough — it also has to ask for focus explicitly, or it
    /// appears silently behind whatever the user was doing.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
