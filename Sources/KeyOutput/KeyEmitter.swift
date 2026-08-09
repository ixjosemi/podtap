import AppKit
import CoreGraphics
import Foundation

/// Sintetiza en el sistema los eventos que PodTap debe producir.
///
/// Dos caminos muy distintos conviven aquí:
///
/// - La **tecla configurable** usa `CGEvent`, API pública y estable.
/// - El **play/pause** no tiene equivalente público. Al secuestrar el
///   dispositivo HID, el evento original deja de existir, así que hay que
///   reconstruirlo a mano con un `NSEvent.systemDefined` y los valores mágicos
///   que macOS espera. Es la única deuda no documentada del proyecto y está
///   deliberadamente confinada a este fichero.
public final class KeyEmitter {
    /// `NX_KEYTYPE_PLAY`, de IOKit/hidsystem/ev_keymap.h.
    private static let mediaKeyPlay: Int32 = 16

    private let eventSource: CGEventSource?

    public init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
    }

    /// Baja la tecla configurada y la deja pulsada.
    public func pressDown(_ combination: KeyCombination) {
        postKey(combination, keyDown: true)
    }

    /// Suelta la tecla configurada.
    public func releaseUp(_ combination: KeyCombination) {
        postKey(combination, keyDown: false)
    }

    private func postKey(_ combination: KeyCombination, keyDown: Bool) {
        guard
            let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(combination.keyCode),
                keyDown: keyDown
            )
        else { return }

        event.flags = combination.flags
        event.post(tap: .cghidEventTap)
    }

    /// Reemite un play/pause completo (pulsar y soltar) al sistema.
    public func tapPlayPause() {
        postMediaKey(down: true)
        postMediaKey(down: false)
    }

    private func postMediaKey(down: Bool) {
        // Los flags 0xA00/0xB00 y el bitfield de data1 no están documentados:
        // son el contrato de facto que usan todas las apps de media keys de
        // macOS. Si Apple los cambia, se rompe el passthrough de play/pause,
        // no la captura del botón.
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let state: Int = down ? 0xA : 0xB
        let data1 = Int((Self.mediaKeyPlay << 16) | Int32(state << 8))

        guard
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
        else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
