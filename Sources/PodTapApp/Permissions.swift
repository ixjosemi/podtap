import AppKit
import ApplicationServices
import HIDInput
import SwiftUI

/// Los dos permisos que PodTap necesita, y por qué.
///
/// Se piden por separado y de forma explícita en la interfaz en lugar de
/// dejar que macOS los saque por sorpresa: así el usuario entiende qué está
/// concediendo y puede recuperarse si dijo que no.
enum SystemPermission: CaseIterable, Identifiable {
    /// Leer el botón del mando.
    case inputMonitoring
    /// Enviar la tecla configurada a otras apps.
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .inputMonitoring: return "Monitorización de entrada"
        case .accessibility: return "Accesibilidad"
        }
    }

    var rationale: String {
        switch self {
        case .inputMonitoring:
            return "Para leer el botón del mando de los EarPods."
        case .accessibility:
            return "Para enviar la tecla configurada a la app en la que escribes."
        }
    }

    var isGranted: Bool {
        switch self {
        case .inputMonitoring: return EarPodsButtonMonitor.hasInputMonitoringAccess
        case .accessibility: return AXIsProcessTrusted()
        }
    }

    /// Provoca el diálogo del sistema. Solo aparece la primera vez; después
    /// macOS exige ir a Ajustes, que es lo que hace `openSystemSettings`.
    func request() {
        switch self {
        case .inputMonitoring:
            EarPodsButtonMonitor.requestInputMonitoringAccess()
        case .accessibility:
            let options =
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func openSystemSettings() {
        let anchor =
            switch self {
            case .inputMonitoring: "Privacy_ListenEvent"
            case .accessibility: "Privacy_Accessibility"
            }
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
