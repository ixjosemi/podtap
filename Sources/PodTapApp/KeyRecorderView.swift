import KeyOutput
import SwiftUI

/// Field that captures the combination PodTap will send.
///
/// Handles all three shapes of shortcut, which macOS reports very differently:
///
/// - `⌘S` and friends arrive as a key press carrying its modifiers.
/// - `⌃⇧` and friends produce no key event at all, only modifier transitions.
/// - Globe / Fn produces a modifier transition that never reaches an app's own
///   event stream, which is why the capture happens in `ShortcutRecorder` at
///   the level below.
struct KeyRecorderView: View {
    @Binding var combination: KeyCombination

    @StateObject private var recorder = ShortcutRecorder()
    /// Set when the event tap cannot be created, which in practice means
    /// Accessibility is missing.
    @State private var isBlocked = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(.body, design: .rounded))
                    .frame(minWidth: 150)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .tint(recorder.isRecording ? .accentColor : nil)
            .help(
                "Click, then press the key or modifiers PodTap should hold. "
                    + "Escape cancels."
            )

            if isBlocked {
                Text("Grant Accessibility to record a shortcut.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { recorder.cancel() }
    }

    /// Echoing the modifiers as they are held makes it obvious that a
    /// modifier-only shortcut is being captured rather than ignored.
    private var label: String {
        guard recorder.isRecording else { return combination.displayName }
        return recorder.heldCombination.isEmpty
            ? "Press keys…" : recorder.heldCombination.displayName
    }

    private func toggleRecording() {
        guard !recorder.isRecording else {
            recorder.cancel()
            return
        }

        isBlocked = !recorder.start { recorded in
            combination = recorded
        }
    }
}
