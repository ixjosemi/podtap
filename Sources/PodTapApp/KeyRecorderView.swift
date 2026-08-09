import AppKit
import KeyOutput
import SwiftUI

/// Field that captures the combination PodTap will send.
///
/// While recording it installs a local keyboard monitor and **swallows** the
/// event, so the keystroke never lands in the window itself — otherwise
/// recording ⌘Q would quit the app on the spot.
struct KeyRecorderView: View {
    @Binding var combination: KeyCombination

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Press a combination…" : combination.displayName)
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 140)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .help("The key PodTap holds down while you hold the remote button.")
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels without changing anything, which is what everyone
            // expects from a shortcut recorder.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let modifiers = UInt64(
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            combination = KeyCombination(keyCode: event.keyCode, modifierFlags: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}
