import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject var preferences: Preferences

    /// Permissions send no change notifications: the user grants them in
    /// System Settings, outside the app. They are re-read periodically so the
    /// interface does not sit there lying.
    @State private var permissionRefresh = Date()
    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("EarPods") {
                    StatusBadge(
                        isPositive: controller.isDeviceConnected,
                        positive: "Connected",
                        negative: "Not connected"
                    )
                }
                if controller.isDictating {
                    LabeledContent("Dictation") {
                        StatusBadge(isPositive: true, positive: "Running", negative: "")
                    }
                }
                if let failure = controller.failureMessage {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section("Mapping") {
                Toggle("Enable PodTap", isOn: $preferences.isEnabled)

                LabeledContent("Key to hold") {
                    KeyRecorderView(combination: $preferences.outputCombination)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Hold threshold") {
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
                        "Below the threshold the button still sends play/pause. Above it, "
                            + "PodTap holds the key you chose."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Toggle("Show icon in the menu bar", isOn: $preferences.showsMenuBarIcon)
                Text(
                    "With this off, PodTap keeps working in the background. Open the app "
                        + "again from Finder to get back here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                ForEach(SystemPermission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        isGranted: permission.isGranted(
                            isReadingDevice: controller.isReadingDevice),
                        refreshToken: permissionRefresh
                    )
                }
            }

            Section {
                LabeledContent("Version", value: preferences.appVersion)
                Button("Run setup again…") { controller.showOnboarding() }
                Link(
                    "Source code on GitHub",
                    destination: URL(string: "https://github.com/ixjosemi/podtap")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
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
    let isGranted: Bool
    /// Exists only to force a redraw from the timer.
    let refreshToken: Date

    var body: some View {
        LabeledContent {
            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                PermissionActions(permission: permission)
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
