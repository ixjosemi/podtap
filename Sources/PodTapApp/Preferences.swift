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
        static let holdThreshold = "holdThresholdSeconds"
        static let isEnabled = "isEnabled"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let hasCompletedSetup = "hasCompletedSetup"
    }

    /// Range offered in the interface. The minimum leaves headroom over the
    /// longest taps measured on real hardware (231 ms).
    static let thresholdRange: ClosedRange<Double> = 0.25...1.0

    @Published var outputCombination: KeyCombination {
        didSet { persistCombination() }
    }

    @Published var holdThreshold: Double {
        didSet { defaults.set(holdThreshold, forKey: Key.holdThreshold) }
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

        let storedThreshold = defaults.double(forKey: Key.holdThreshold)
        holdThreshold = storedThreshold > 0 ? storedThreshold : 0.3

        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup)
    }

    private func persistCombination() {
        guard let encoded = try? JSONEncoder().encode(outputCombination) else { return }
        defaults.set(encoded, forKey: Key.combination)
    }

    /// Version shown in the interface, read from the bundle.
    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
