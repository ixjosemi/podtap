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

    var isGranted: Bool {
        switch self {
        case .inputMonitoring: return EarPodsButtonMonitor.hasInputMonitoringAccess
        case .accessibility: return AXIsProcessTrusted()
        }
    }

    static var allGranted: Bool {
        allCases.allSatisfy(\.isGranted)
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
