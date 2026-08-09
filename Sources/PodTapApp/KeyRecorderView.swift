import AppKit
import KeyOutput
import SwiftUI

/// Field that captures the combination PodTap will send.
///
/// Handles three shapes of shortcut, which the event system reports very
/// differently:
///
/// - `⌘S` and friends: a `keyDown` carrying its modifiers.
/// - `⌃⇧` and friends: no key event at all, only modifier transitions. Held
///   modifiers are remembered and committed when the last one is let go.
/// - Globe / Fn: the same as above, since macOS treats it as a modifier.
///
/// While recording it **swallows** every event, so a keystroke never lands in
/// the window itself — otherwise recording ⌘Q would quit the app on the spot.
struct KeyRecorderView: View {
    @Binding var combination: KeyCombination

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    /// The largest modifier set seen during the current press, so releasing
    /// ⌃⇧ one key at a time still records both.
    @State private var heldModifiers: UInt64 = 0

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? promptText : combination.displayName)
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 150)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .help("The key or modifiers PodTap holds down while you hold the remote button.")
        .onDisappear(perform: stopRecording)
    }

    /// Echoing the modifiers as they are held makes it obvious that a
    /// modifier-only shortcut is being captured rather than ignored.
    private var promptText: String {
        heldModifiers == 0
            ? "Press keys…"
            : KeyCombination(keyCode: nil, modifierFlags: heldModifiers).displayName
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        heldModifiers = 0

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            event in
            event.type == .flagsChanged ? capture(modifiers: event) : capture(key: event)
        }
    }

    private func capture(key event: NSEvent) -> NSEvent? {
        let modifiers = supportedModifiers(in: event)

        // Escape on its own cancels, which is what everyone expects. With
        // modifiers held it is a legitimate shortcut, so it is recorded.
        if event.keyCode == 53 && modifiers == 0 {
            stopRecording()
            return nil
        }

        commit(KeyCombination(keyCode: event.keyCode, modifierFlags: modifiers))
        return nil
    }

    private func capture(modifiers event: NSEvent) -> NSEvent? {
        let current = supportedModifiers(in: event)

        if current != 0 {
            // Still building the combination — the user may add more keys.
            heldModifiers = current
            return nil
        }

        // Everything released: what was held is the shortcut.
        if heldModifiers != 0 {
            commit(KeyCombination(keyCode: nil, modifierFlags: heldModifiers))
        }
        return nil
    }

    private func supportedModifiers(in event: NSEvent) -> UInt64 {
        UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
    }

    private func commit(_ recorded: KeyCombination) {
        guard !recorded.isEmpty else { return }
        combination = recorded
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        heldModifiers = 0
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}
