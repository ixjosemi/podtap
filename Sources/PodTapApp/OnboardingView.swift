import AppKit
import SwiftUI

/// First-run setup. Walks through the two permissions and the key choice
/// before the app is ever expected to work.
///
/// Permissions are the first thing a new user meets on purpose: without them
/// PodTap silently does nothing, and a silent no-op is the worst possible
/// first impression.
struct OnboardingView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject var preferences: Preferences
    /// Called when setup finishes or is skipped, so the window can close and
    /// the controller can start listening.
    let onFinish: () -> Void

    @State private var step: SetupStep = .welcome
    @State private var permissionRefresh = Date()

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.top, 36)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 580, height: 520)
        .onReceive(permissionTimer) { _ in permissionRefresh = Date() }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .permissions: permissionsStep
        case .shortcut: shortcutStep
        case .ready: readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 108, height: 108)

            Text("Welcome to PodTap")
                .font(.system(size: 28, weight: .bold))

            Text("Your EarPods remote button becomes any key you want.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 14) {
                GestureRow(
                    symbol: "hand.tap",
                    title: "Short tap",
                    detail: "Play / pause, exactly as before."
                )
                GestureRow(
                    symbol: "waveform",
                    title: "Press and hold",
                    detail: "Holds the key you choose, then releases it."
                )
            }
            .padding(.top, 6)

            Spacer()
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Grant two permissions",
                subtitle: "macOS requires both before PodTap can do anything."
            )

            ForEach(SystemPermission.allCases) { permission in
                PermissionCard(
                    permission: permission,
                    isGranted: permission.isGranted(
                        isReadingDevice: controller.isReadingDevice),
                    refreshToken: permissionRefresh
                )
            }

            Label(
                "Input Monitoring only takes effect once PodTap restarts, so use "
                    + "Quit & Reopen if the switch is already on.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                title: "Choose your key",
                subtitle: "PodTap holds this key down while you hold the remote button."
            )

            HStack(spacing: 16) {
                Text("Key to hold")
                Spacer()
                KeyRecorderView(combination: $preferences.outputCombination)
            }
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text("Hold threshold")
                HStack {
                    Slider(
                        value: $preferences.holdThreshold,
                        in: Preferences.thresholdRange,
                        step: 0.05
                    )
                    Text("\(Int(preferences.holdThreshold * 1000)) ms")
                        .monospacedDigit()
                        .frame(width: 66, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                Text("Anything shorter stays a play/pause tap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            Label(
                "Set this same key as the shortcut in your dictation app.",
                systemImage: "arrow.turn.down.right"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var readyStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(.green)

            Text("You're set")
                .font(.system(size: 28, weight: .bold))

            Text(summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(
                preferences.showsMenuBarIcon
                    ? "PodTap lives in the menu bar. You can reopen these settings from there."
                    : "PodTap runs in the background. Open it again from Finder to change settings."
            )
            .font(.callout)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)

            Spacer()
        }
    }

    /// Built as a plain `String` so SwiftUI does not try to read it as a
    /// localised key with interpolation.
    private var summary: String {
        let key = preferences.outputCombination.displayName
        return "Hold the remote button to send \(key). Tap it for play/pause."
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            ForEach(SetupStep.allCases, id: \.self) { dot in
                Circle()
                    .fill(dot == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }

            Spacer()

            if step == .permissions && !SystemPermission.allGranted(isReadingDevice: controller.isReadingDevice) {
                Button("Skip for now") { advance() }
                    .buttonStyle(.link)
            }

            if step != .welcome {
                Button("Back") { retreat() }
            }

            Button(step == .ready ? "Start using PodTap" : "Continue") { advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(step == .permissions && !SystemPermission.allGranted(isReadingDevice: controller.isReadingDevice))
        }
    }

    private func advance() {
        guard let next = step.next else {
            preferences.hasCompletedSetup = true
            onFinish()
            return
        }
        step = next
    }

    private func retreat() {
        guard let previous = step.previous else { return }
        step = previous
    }
}

enum SetupStep: Int, CaseIterable {
    case welcome, permissions, shortcut, ready

    var next: SetupStep? { SetupStep(rawValue: rawValue + 1) }
    var previous: SetupStep? { SetupStep(rawValue: rawValue - 1) }
}

// MARK: - Pieces

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 24, weight: .bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
    }
}

private struct GestureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 34)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PermissionCard: View {
    let permission: SystemPermission
    let isGranted: Bool
    /// Exists only to force a redraw from the timer: macOS sends no
    /// notification when permissions change.
    let refreshToken: Date

    var body: some View {
        let granted = isGranted

        HStack(alignment: .top, spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "lock.circle")
                .font(.title2)
                .foregroundStyle(granted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title).fontWeight(.semibold)
                Text(permission.rationale).font(.callout).foregroundStyle(.secondary)
                Text(permission.systemSettingsHint).font(.caption).foregroundStyle(.tertiary)
            }

            Spacer()

            if granted {
                Text("Granted").foregroundStyle(.green).fontWeight(.medium)
            } else {
                PermissionActions(permission: permission)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
