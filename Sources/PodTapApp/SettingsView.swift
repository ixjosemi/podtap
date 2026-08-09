import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject var preferences: Preferences

    /// Los permisos no notifican cambios: el usuario los concede en Ajustes del
    /// Sistema, fuera de la app. Se reconsultan periódicamente para que la
    /// interfaz no se quede mintiendo.
    @State private var permissionRefresh = Date()
    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Estado") {
                LabeledContent("EarPods") {
                    StatusBadge(
                        isPositive: controller.isDeviceConnected,
                        positive: "Conectados",
                        negative: "No conectados"
                    )
                }
                if controller.isDictating {
                    LabeledContent("Dictado") {
                        StatusBadge(isPositive: true, positive: "En curso", negative: "")
                    }
                }
                if let failure = controller.failureMessage {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section("Mapeo") {
                Toggle("Activar PodTap", isOn: $preferences.isEnabled)

                LabeledContent("Tecla al mantener") {
                    KeyRecorderView(combination: $preferences.outputCombination)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Umbral de mantenido") {
                        Text("\(Int(preferences.holdThreshold * 1000)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $preferences.holdThreshold,
                        in: Preferences.thresholdRange,
                        step: 0.05
                    )
                    Text(
                        "Por debajo del umbral, el botón hace play/pause como siempre. "
                            + "Por encima, mantiene pulsada la tecla elegida."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Permisos") {
                ForEach(SystemPermission.allCases) { permission in
                    PermissionRow(permission: permission, refreshToken: permissionRefresh)
                }
            }

            Section {
                LabeledContent("Versión", value: preferences.appVersion)
                Link(
                    "Código fuente en GitHub",
                    destination: URL(string: "https://github.com/ixjosemi/podtap")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(permissionTimer) { _ in permissionRefresh = Date() }
    }
}

private struct StatusBadge: View {
    let isPositive: Bool
    let positive: String
    let negative: String

    var body: some View {
        Label(
            isPositive ? positive : negative,
            systemImage: isPositive ? "checkmark.circle.fill" : "circle.dashed"
        )
        .foregroundStyle(isPositive ? .green : .secondary)
    }
}

private struct PermissionRow: View {
    let permission: SystemPermission
    /// Solo existe para forzar el redibujado desde el temporizador.
    let refreshToken: Date

    var body: some View {
        let granted = permission.isGranted

        LabeledContent {
            if granted {
                Label("Concedido", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Conceder…") {
                    permission.request()
                    permission.openSystemSettings()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
