import Foundation
import KeyOutput
import SwiftUI

/// Preferencias del usuario, respaldadas por `UserDefaults`.
///
/// Todo lo que la app necesita saber para funcionar se configura desde la
/// interfaz: no hay nada que editar a mano ni ningún fichero de configuración.
@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let combination = "outputKeyCombination"
        static let holdThreshold = "holdThresholdSeconds"
        static let isEnabled = "isEnabled"
    }

    /// Rango ofrecido en la interfaz. El mínimo deja margen sobre las
    /// pulsaciones cortas medidas en hardware real (hasta 231 ms).
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
    }

    private func persistCombination() {
        guard let encoded = try? JSONEncoder().encode(outputCombination) else { return }
        defaults.set(encoded, forKey: Key.combination)
    }

    /// Versión mostrada en la interfaz, leída del bundle.
    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
