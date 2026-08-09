import Foundation

/// Fase física del botón del mando, tal y como la reporta el dispositivo HID.
///
/// Los EarPods USB-C publican en la Consumer Page (0x0C) el usage `PlayPause`
/// (0x00CD) con transiciones reales de valor 1/0. macOS colapsa ese par en un
/// único toggle de reproducción en una capa superior; nosotros trabajamos por
/// debajo y conservamos la duración de la pulsación.
public enum ButtonPhase: Sendable, Equatable {
    case pressed
    case released
}

/// Un evento de botón con su marca temporal monótona, en segundos.
///
/// El tiempo se inyecta en lugar de leerse de un reloj global para que la
/// clasificación sea determinista y testeable sin hardware.
public struct ButtonEvent: Sendable, Equatable {
    public let phase: ButtonPhase
    public let timestamp: TimeInterval

    public init(phase: ButtonPhase, timestamp: TimeInterval) {
        self.phase = phase
        self.timestamp = timestamp
    }
}

/// Lo que la app debe provocar en el sistema. Deliberadamente abstracto: este
/// módulo no sabe nada de `CGEvent` ni de qué tecla está configurada.
public enum GestureIntent: Sendable, Equatable {
    /// Reemitir play/pause al sistema. Necesario porque, al secuestrar el
    /// dispositivo, el evento original ya no llega a nadie.
    case emitPlayPause
    /// Bajar la tecla configurada y mantenerla.
    case beginDictation
    /// Soltar la tecla configurada.
    case endDictation
}

/// Estado observable del clasificador. Público para que la UI pueda reflejarlo
/// en la barra de menús y para poder afirmar sobre él en los tests.
public enum ClassifierState: Sendable, Equatable {
    /// Botón arriba, nada en curso.
    case idle
    /// Botón abajo desde `since`, aún sin cruzar el umbral de mantenido.
    case pressing(since: TimeInterval)
    /// Umbral cruzado: la tecla está bajada y el dictado en curso.
    case dictating
}

/// Traduce pulsaciones físicas del botón en intenciones, aplicando la política
/// «toque corto = play/pause, mantener = dictado».
///
/// Es un `struct` sin dependencias externas: el mismo valor puede reproducirse
/// en un test alimentándolo con una secuencia de eventos y ticks.
public struct GestureClassifier: Sendable {
    /// A partir de cuántos segundos una pulsación deja de ser un toque.
    ///
    /// Medido en el hardware real: los toques del usuario caen entre 79 y
    /// 231 ms, y un mantenido deliberado se va por encima de 1700 ms.
    public var holdThreshold: TimeInterval

    public private(set) var state: ClassifierState

    public init(holdThreshold: TimeInterval = 0.3, state: ClassifierState = .idle) {
        self.holdThreshold = holdThreshold
        self.state = state
    }

    /// Procesa una transición del botón y devuelve las intenciones resultantes.
    ///
    /// - TODO: implementar. Ver `tests/GestureCoreTests/GestureClassifierTests.swift`
    ///   para el comportamiento esperado, incluidos los casos degenerados.
    public mutating func handle(_ event: ButtonEvent) -> [GestureIntent] {
        []
    }

    /// Avance del reloj. El clasificador no puede detectar por sí solo que una
    /// pulsación se ha convertido en mantenida —no llega ningún evento HID al
    /// cruzar el umbral—, así que la capa de entrada le da pulsos periódicos.
    ///
    /// Disparar aquí, y no al soltar, es lo que hace que el push-to-talk sea
    /// real: el dictado arranca mientras sigues manteniendo el botón.
    public mutating func tick(at now: TimeInterval) -> [GestureIntent] {
        guard case .pressing(let since) = state else { return [] }
        guard now - since >= holdThreshold else { return [] }

        state = .dictating
        return [.beginDictation]
    }

    /// Aborta cualquier gesto en curso sin producir efectos espurios.
    ///
    /// Se invoca cuando los EarPods se desconectan o el sistema se suspende. Si
    /// hay un dictado abierto hay que cerrarlo: si no, la tecla se queda bajada
    /// para siempre y la app de dictado graba sin fin.
    public mutating func interrupt() -> [GestureIntent] {
        defer { state = .idle }
        return state == .dictating ? [.endDictation] : []
    }
}
