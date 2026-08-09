import AppKit
import KeyOutput
import SwiftUI

/// Campo para capturar la combinación que PodTap enviará.
///
/// Mientras graba instala un monitor local de teclado y **se traga** el evento,
/// para que la pulsación no acabe escribiéndose en la propia ventana.
struct KeyRecorderView: View {
    @Binding var combination: KeyCombination

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Pulsa una combinación…" : combination.displayName)
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 140)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .help("Elige la tecla que PodTap mantendrá pulsada mientras mantengas el botón del mando.")
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancela sin cambiar nada, que es lo que espera cualquiera.
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
