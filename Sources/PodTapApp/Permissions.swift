import AppKit
import ApplicationServices
import HIDInput
import SwiftUI

/// The two permissions PodTap needs, and why.
///
/// They are requested explicitly during setup rather than letting macOS spring
/// them on the user mid-use, so it is clear what is being granted and how to
/// recover from having said no.
enum SystemPermission: CaseIterable, Identifiable {
    /// Reading the remote button.
    case inputMonitoring
    /// Sending the configured key to other apps.
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        }
    }

    var rationale: String {
        switch self {
        case .inputMonitoring:
            return "Lets PodTap read the button on your EarPods remote."
        case .accessibility:
            return "Lets PodTap send the key you chose to whatever app you are typing in."
        }
    }

    var systemSettingsHint: String {
        switch self {
        case .inputMonitoring:
            return "Privacy & Security › Input Monitoring"
        case .accessibility:
            return "Privacy & Security › Accessibility"
        }
    }

    /// Whether the permission is actually in effect.
    ///
    /// Input Monitoring needs the extra evidence: `IOHIDCheckAccess` answers
    /// from a per-process cache, so an app that was running when the user
    /// ticked the box goes on reporting denial indefinitely. Successfully
    /// reading the device settles the question in a way the API cannot.
    func isGranted(isReadingDevice: Bool) -> Bool {
        switch self {
        case .inputMonitoring:
            return isReadingDevice || EarPodsButtonMonitor.hasInputMonitoringAccess
        case .accessibility:
            return AXIsProcessTrusted()
        }
    }

    /// True when the cached answer is the only thing standing in the way, so
    /// the interface can offer a relaunch instead of sending the user back to
    /// System Settings to re-tick a box that is already ticked.
    var isResolvedByRelaunch: Bool { self == .inputMonitoring }

    static func allGranted(isReadingDevice: Bool) -> Bool {
        allCases.allSatisfy { $0.isGranted(isReadingDevice: isReadingDevice) }
    }

    /// Triggers the system dialog, and registers the app in the relevant
    /// System Settings list so the user only has to flip a switch rather than
    /// hunt for the app under "+".
    ///
    /// Deliberately does not open System Settings: doing both at once steals
    /// focus from the dialog this call is trying to raise.
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

/// What to offer when a permission is not in effect. Shared by setup and
/// settings so the recovery path cannot drift between the two.
struct PermissionActions: View {
    let permission: SystemPermission

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Requesting and opening System Settings are separate actions on
            // purpose: firing both together steals focus from the very dialog
            // the request is raising.
            Button("Grant…") { permission.request() }
                .buttonStyle(.borderedProminent)

            Button("Open System Settings") { permission.openSystemSettings() }
                .buttonStyle(.link)
                .font(.caption)

            if permission.isResolvedByRelaunch {
                Button("Quit & Reopen") { controller.relaunch() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Already enabled it? macOS only notices after PodTap restarts.")
            }
        }
    }
}
