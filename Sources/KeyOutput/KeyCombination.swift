import CoreGraphics
import Foundation

/// Una combinación de teclas que PodTap mantendrá pulsada mientras el usuario
/// mantenga el botón del mando.
///
/// Se guarda por código de tecla virtual y no por carácter: así el mapeo
/// sobrevive a cambios de distribución de teclado.
public struct KeyCombination: Sendable, Equatable, Codable {
    public var keyCode: UInt16
    /// Subconjunto de `CGEventFlags` en crudo. Solo se conservan los
    /// modificadores que el usuario puede pulsar.
    public var modifierFlags: UInt64

    public init(keyCode: UInt16, modifierFlags: UInt64 = 0) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags & Self.supportedModifiers
    }

    /// F13: una tecla real que macOS deja libre y que ninguna app reclama.
    /// Buen punto de partida porque no colisiona con nada.
    public static let defaultCombination = KeyCombination(keyCode: 105)

    static let supportedModifiers: UInt64 =
        CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue

    public var flags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlags)
    }

    /// Representación para la interfaz, con los símbolos habituales de macOS
    /// en el orden canónico ⌃⌥⇧⌘.
    public var displayName: String {
        var symbols = ""
        if modifierFlags & CGEventFlags.maskControl.rawValue != 0 { symbols += "⌃" }
        if modifierFlags & CGEventFlags.maskAlternate.rawValue != 0 { symbols += "⌥" }
        if modifierFlags & CGEventFlags.maskShift.rawValue != 0 { symbols += "⇧" }
        if modifierFlags & CGEventFlags.maskCommand.rawValue != 0 { symbols += "⌘" }
        return symbols + (Self.keyNames[keyCode] ?? "Tecla \(keyCode)")
    }

    /// Nombres de teclas virtuales de macOS. Cubre lo que alguien elegiría como
    /// atajo global; el resto cae en el nombre genérico con el código.
    static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Espacio", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Inicio", 119: "Fin", 116: "Re Pág", 121: "Av Pág", 114: "Ayuda",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]
}
