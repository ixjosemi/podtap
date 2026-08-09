// Spike de diagnóstico: observa (sin secuestrar) los eventos HID de la página
// Consumer (0x0C) para descubrir qué emite el botón de los EarPods USB-C.
//
// Ejecutar:  swift hidprobe.swift
// Requiere:  Ajustes > Privacidad y Seguridad > Monitorización de entrada > [terminal]
//
// NO usa kIOHIDOptionsTypeSeizeDevice a propósito: durante el diagnóstico
// queremos que el play/pause siga funcionando con normalidad.

import Foundation
import IOKit
import IOKit.hid

// Sin buffer: el proceso corre en segundo plano con stdout redirigido a fichero,
// y queremos ver cada evento en el momento en que ocurre.
setvbuf(stdout, nil, _IONBF, 0)

let consumerPage = 0x0C

/// Nombres de la HID Usage Table, sección Consumer Page (0x0C).
/// Solo los que puede plausiblemente emitir un mando de auriculares.
let consumerUsageNames: [UInt32: String] = [
    0x00B0: "Play",
    0x00B1: "Pause",
    0x00B3: "FastForward",
    0x00B4: "Rewind",
    0x00B5: "ScanNextTrack",
    0x00B6: "ScanPreviousTrack",
    0x00B7: "Stop",
    0x00CD: "PlayPause",
    0x00CF: "VoiceCommand",
    0x00E2: "Mute",
    0x00E9: "VolumeIncrement",
    0x00EA: "VolumeDecrement",
    0x0221: "ACSearch",
]

func property(_ device: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(device, key as CFString)
}

func describe(_ device: IOHIDDevice) -> String {
    let product = property(device, kIOHIDProductKey) as? String ?? "?"
    let transport = property(device, kIOHIDTransportKey) as? String ?? "?"
    let vendorID = property(device, kIOHIDVendorIDKey) as? Int ?? 0
    let productID = property(device, kIOHIDProductIDKey) as? Int ?? 0
    return String(
        format: "%@ [vid=0x%04X pid=0x%04X transport=%@]",
        product, vendorID, productID, transport
    )
}

/// Marca temporal del evento anterior, para medir la separación entre
/// pulsaciones y saber si una doble pulsación es distinguible.
nonisolated(unsafe) var previousEventTime: Date?

let inputCallback: IOHIDValueCallback = { _, _, sender, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)

    guard usagePage == consumerPage else { return }

    let now = Date()
    let delta = previousEventTime.map { now.timeIntervalSince($0) * 1000 }
    previousEventTime = now

    let deviceLabel: String
    if let sender {
        deviceLabel = describe(unsafeBitCast(sender, to: IOHIDDevice.self))
    } else {
        deviceLabel = "?"
    }

    let usageName = consumerUsageNames[usage] ?? "desconocido"
    let deltaText = delta.map { String(format: "  +%.0f ms", $0) } ?? ""
    let stateText = intValue == 1 ? "DOWN" : (intValue == 0 ? "UP  " : "val=\(intValue)")

    print(
        String(
            format: "%@  usage=0x%04X %-18@ %@%@",
            stateText, usage, usageName, deviceLabel, deltaText
        )
    )
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

// Matchear cualquier dispositivo que publique elementos de la página Consumer.
IOHIDManagerSetDeviceMatching(
    manager,
    [kIOHIDDeviceUsagePageKey: consumerPage] as CFDictionary
)

IOHIDManagerRegisterInputValueCallback(manager, inputCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    FileHandle.standardError.write(
        Data(
            """
            ERROR: IOHIDManagerOpen falló (0x\(String(openResult, radix: 16))).
            Lo más probable: falta permiso de Monitorización de entrada.
            Ajustes del Sistema > Privacidad y Seguridad > Monitorización de entrada.

            """.utf8
        )
    )
    exit(1)
}

let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
print("Dispositivos Consumer (0x0C) detectados:")
for device in devices.sorted(by: { describe($0) < describe($1) }) {
    print("  - \(describe(device))")
}
print("""

Escuchando. Prueba en este orden y observa la separación en ms:
  1. pulsación simple
  2. doble pulsación rápida
  3. triple pulsación
  4. mantener pulsado ~2s
Ctrl-C para salir.

""")

CFRunLoopRun()
