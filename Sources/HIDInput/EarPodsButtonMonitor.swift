import Foundation
import IOKit
import IOKit.hid

public enum HIDInputError: LocalizedError {
    case inputMonitoringDenied
    case seizeFailed(IOReturn)

    public var errorDescription: String? {
        switch self {
        case .inputMonitoringDenied:
            return "PodTap necesita permiso de Monitorización de entrada para leer el botón del mando."
        case .seizeFailed(let code):
            return "No se pudo tomar el control del dispositivo (IOReturn 0x\(String(code, radix: 16)))."
        }
    }
}

/// Fase física del botón, replicada aquí para que `HIDInput` no dependa de
/// `GestureCore`: la capa de entrada no debería saber nada de clasificación.
public enum ButtonTransition: Sendable, Equatable {
    case pressed
    case released
}

/// Abre en exclusiva el mando de los EarPods USB-C y publica sus pulsaciones.
///
/// Usa `kIOHIDOptionsTypeSeizeDevice`, lo que impide que macOS convierta la
/// pulsación en un play/pause. Esa reemisión, cuando procede, es
/// responsabilidad de la capa de salida.
public final class EarPodsButtonMonitor {
    /// EarPods USB-C de Apple.
    private static let vendorID = 0x05AC
    private static let productID = 0x110B
    /// HID Consumer Page y el usage concreto del botón.
    private static let consumerPage: UInt32 = 0x0C
    private static let consumerControlUsage = 0x01
    private static let playPauseUsage: UInt32 = 0x00CD

    /// Se invoca en la cola principal por cada transición del botón, con una
    /// marca temporal monótona en segundos.
    public var onButton: ((ButtonTransition, TimeInterval) -> Void)?
    /// Se invoca en la cola principal cuando los EarPods se conectan o
    /// desconectan.
    public var onConnectionChange: ((Bool) -> Void)?

    public private(set) var isConnected = false

    private var manager: IOHIDManager?

    public init() {}

    deinit {
        stop()
    }

    /// Comprueba el permiso sin solicitarlo, para poder pintar el estado en la
    /// interfaz sin provocar diálogos del sistema.
    public static var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Solicita el permiso, lo que hace aparecer el diálogo del sistema la
    /// primera vez.
    @discardableResult
    public static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public func start() throws {
        guard Self.hasInputMonitoringAccess else {
            throw HIDInputError.inputMonitoringDenied
        }
        stop()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Matcheamos la interfaz Consumer concreta y no solo el vid/pid: los
        // EarPods publican también una interfaz vendor-defined cuyo secuestro
        // no aporta nada y cuyos efectos no están medidos.
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey: Self.vendorID,
                kIOHIDProductIDKey: Self.productID,
                kIOHIDDeviceUsagePageKey: Int(Self.consumerPage),
                kIOHIDDeviceUsageKey: Self.consumerControlUsage,
            ] as CFDictionary
        )

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(manager, Self.valueCallback, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
            )
            throw HIDInputError.seizeFailed(result)
        }

        self.manager = manager
        updateConnectionState(
            to: !((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.isEmpty ?? true)
        )
    }

    /// Libera el dispositivo y lo devuelve al sistema. Idempotente.
    public func stop() {
        guard let manager else { return }
        self.manager = nil

        IOHIDManagerUnscheduleFromRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        updateConnectionState(to: false)
    }

    private func updateConnectionState(to connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onConnectionChange?(connected)
    }

    // MARK: - Puentes desde las callbacks de C

    private func receive(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == Self.consumerPage,
            IOHIDElementGetUsage(element) == Self.playPauseUsage
        else { return }

        let transition: ButtonTransition =
            IOHIDValueGetIntegerValue(value) == 1 ? .pressed : .released
        let timestamp = ProcessInfo.processInfo.systemUptime

        onButton?(transition, timestamp)
    }

    private static let valueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        Unmanaged<EarPodsButtonMonitor>.fromOpaque(context).takeUnretainedValue()
            .receive(value: value)
    }

    private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<EarPodsButtonMonitor>.fromOpaque(context).takeUnretainedValue()
            .updateConnectionState(to: true)
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<EarPodsButtonMonitor>.fromOpaque(context).takeUnretainedValue()
            .updateConnectionState(to: false)
    }
}
