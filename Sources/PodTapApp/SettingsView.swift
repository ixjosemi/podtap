import AppKit
import GestureCore
import SwiftUI

/// Deliberately sparse, and shaped like a System Settings pane: named sections
/// over grouped boxes, a real title bar, no header of its own.
///
/// Two rules keep it that way. Nothing explains itself in prose — the setup
/// flow is where PodTap teaches, and repeating it here turned the window into a
/// leaflet. And permissions only appear while they are missing: two rows saying
/// "Granted" are noise for the entire life of the app, so once they are in
/// effect the whole section disappears.
struct SettingsView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject var preferences: Preferences

    /// Permissions send no change notifications: the user grants them in
    /// System Settings, outside the app. They are re-read periodically so the
    /// interface does not sit there lying.
    @State private var permissionRefresh = Date()
    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var status: AppStatus {
        AppStatus(
            isEnabled: preferences.isEnabled,
            isDeviceConnected: controller.isDeviceConnected,
            isDictating: controller.isDictating
        )
    }

    private var missingPermissions: [SystemPermission] {
        SystemPermission.allCases.filter {
            !$0.isGranted(isReadingDevice: controller.isReadingDevice)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 16) {
                generalSection
                shortcutSection
                if !missingPermissions.isEmpty { permissionsSection }
                if let failure = controller.failureMessage { FailureNote(message: failure) }
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowBackdrop().ignoresSafeArea())
        .onReceive(permissionTimer) { _ in permissionRefresh = Date() }
    }

    // MARK: - Header

    /// Full-bleed, and washed with the user's own accent colour fading out
    /// downwards. That wash is the whole point: it gives the window a top
    /// without adding another box, and it picks up whatever accent the Mac is
    /// set to rather than a colour PodTap invented.
    ///
    /// The status lives here rather than in a row, so the one changing thing on
    /// the window is also the one thing in the header.
    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 1) {
                Text("PodTap").font(.system(size: 17, weight: .semibold))
                Text("Dictation switch for wired EarPods")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            StatusIndicator(status: status)
        }
        .padding(.horizontal, 20)
        // Clears the traffic lights, which float over the content.
        .padding(.top, 34)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section("General") {
            SettingsToggle("Enable PodTap", isOn: $preferences.isEnabled)
            RowDivider()
            SettingsToggle("Show in menu bar", isOn: $preferences.showsMenuBarIcon)
            RowDivider()
            DisclosureRow("Setup guide") { controller.showOnboarding() }
        }
    }

    private var shortcutSection: some View {
        Section("Shortcut") {
            SettingsRow {
                Text("Key to send")
                Spacer(minLength: 12)
                KeyRecorderView(combination: $preferences.outputCombination)
            }
        }
    }

    /// Only ever built when something is actually missing, so it can afford to
    /// be blunt about it.
    private var permissionsSection: some View {
        Section("Permissions") {
            ForEach(Array(missingPermissions.enumerated()), id: \.element) { index, permission in
                if index > 0 { RowDivider() }
                SettingsRow {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.trailing, 9)

                    Text(permission.title)

                    Spacer(minLength: 12)

                    PermissionActions(permission: permission, showsRecoveryOptions: false)
                }
                // The reason is one hover away rather than printed under every
                // row: it matters once, when deciding to grant.
                .help(permission.rationale)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(verbatim: "Version \(preferences.appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Build \(preferences.buildNumber)")

            Spacer()

            Link(destination: URL(string: "https://github.com/ixjosemi/podtap")!) {
                Artwork.githubMark
                    .resizable()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("PodTap on GitHub")
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}

// MARK: - Pieces

/// A named group of rows on one pane of glass. Rows are divided, never padded
/// apart: the box is the grouping, so gaps inside it only blur what belongs
/// together.
private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title)
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .glassCard()
        }
    }
}

/// Uniform geometry for anything sitting inside a box, so rows line up across
/// sections no matter what they contain. Always full width: a row that hugs its
/// content leaves the box hugging too.
struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label on the left, switch hard against the right edge, the way every
/// settings row on macOS is laid out. A bare `Toggle` puts the two side by
/// side in the middle instead.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        SettingsRow {
            Text(title)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// A row that takes you somewhere else, marked with the chevron macOS uses for
/// exactly that. The whole row is the target, not just the text.
private struct DisclosureRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsRow {
                Text(title)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.05) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct FailureNote: View {
    let message: String

    var body: some View {
        Label {
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
