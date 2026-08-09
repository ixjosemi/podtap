import Foundation
import KeyOutput
import SwiftUI

/// User preferences, backed by `UserDefaults`.
///
/// Everything PodTap needs is configured from the interface: there is nothing
/// to edit by hand and no configuration file to find.
@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let combination = "outputKeyCombination"
        static let isEnabled = "isEnabled"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let hasCompletedSetup = "hasCompletedSetup"
    }

    @Published var outputCombination: KeyCombination {
        didSet { persistCombination() }
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// When off, PodTap runs purely in the background. Reopening the app from
    /// Finder brings the settings window back, so hiding the icon is never a
    /// one-way door.
    @Published var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    @Published var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: Key.hasCompletedSetup) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.data(forKey: Key.combination),
            let decoded = try? JSONDecoder().decode(KeyCombination.self, from: stored)
        {
            outputCombination = decoded
        } else {
            outputCombination = .defaultCombination
        }

        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup)
    }

    private func persistCombination() {
        guard let encoded = try? JSONEncoder().encode(outputCombination) else { return }
        defaults.set(encoded, forKey: Key.combination)
    }

    /// Version shown in the interface, read from the bundle. The build number
    /// only matters in a bug report, so it stays out of the window and lives
    /// in `buildNumber` for the tooltip.
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
