import AppKit
import Combine
import Foundation
import GestureCore
import HIDInput
import KeyOutput

/// Une la captura del botón, la clasificación del gesto y la síntesis de
/// eventos, y expone a la interfaz el estado observable.
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var isDeviceConnected = false
    @Published private(set) var isDictating = false
    /// Mensaje de error legible, o `nil` si todo va bien.
    @Published private(set) var failureMessage: String?

    let preferences: Preferences

    private let monitor = EarPodsButtonMonitor()
    private let emitter = KeyEmitter()
    private var classifier = GestureClassifier()
    /// Disparo único programado al iniciar una pulsación: es lo que convierte
    /// «sigue pulsado» en un evento, ya que el hardware no avisa al cruzar el
    /// umbral.
    private var holdTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(preferences: Preferences) {
        self.preferences = preferences
        classifier.holdThreshold = preferences.holdThreshold

        monitor.onButton = { [weak self] transition, timestamp in
            self?.handleButton(transition, at: timestamp)
        }
        monitor.onConnectionChange = { [weak self] connected in
            self?.handleConnectionChange(connected)
        }

        preferences.$holdThreshold
            .sink { [weak self] threshold in self?.classifier.holdThreshold = threshold }
            .store(in: &cancellables)

        // `dropFirst` evita actuar sobre el valor inicial: el arranque se hace
        // una sola vez abajo, ya fuera de `init`.
        preferences.$isEnabled
            .dropFirst()
            .sink { [weak self] enabled in enabled ? self?.start() : self?.stop() }
            .store(in: &cancellables)

        AppDelegate.controller = self

        // Diferido al siguiente ciclo del run loop: arrancar dentro de `init`
        // significaría usar `self` antes de que termine de construirse.
        Task { @MainActor [weak self] in self?.start() }
    }

    // MARK: - Ciclo de vida

    func start() {
        guard preferences.isEnabled else { return }
        do {
            try monitor.start()
            failureMessage = nil
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    func stop() {
        abortGesture()
        monitor.stop()
        isDeviceConnected = false
    }

    /// Devuelve el dispositivo al sistema y suelta cualquier tecla pendiente.
    /// Debe llamarse antes de terminar el proceso: si no, el sistema podría
    /// quedarse con la tecla bajada.
    func prepareForTermination() {
        stop()
    }

    // MARK: - Eventos

    private func handleButton(_ transition: ButtonTransition, at timestamp: TimeInterval) {
        let event = ButtonEvent(
            phase: transition == .pressed ? .pressed : .released,
            timestamp: timestamp
        )

        switch transition {
        case .pressed: scheduleHoldTimer()
        case .released: cancelHoldTimer()
        }

        apply(classifier.handle(event))
    }

    private func handleConnectionChange(_ connected: Bool) {
        isDeviceConnected = connected
        // Desconectar con el botón pulsado dejaría la tecla bajada para
        // siempre, y la app de dictado grabando sin fin.
        if !connected { abortGesture() }
    }

    private func abortGesture() {
        cancelHoldTimer()
        apply(classifier.interrupt())
    }

    private func scheduleHoldTimer() {
        cancelHoldTimer()
        holdTimer = Timer.scheduledTimer(
            withTimeInterval: preferences.holdThreshold,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.classifier.tick(at: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func apply(_ intents: [GestureIntent]) {
        for intent in intents {
            switch intent {
            case .emitPlayPause:
                emitter.tapPlayPause()
            case .beginDictation:
                emitter.pressDown(preferences.outputCombination)
                isDictating = true
            case .endDictation:
                emitter.releaseUp(preferences.outputCombination)
                isDictating = false
            }
        }
    }
}
