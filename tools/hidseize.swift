// Spike 2: comprobar que kIOHIDOptionsTypeSeizeDevice sobre los EarPods
// (a) lo concede macOS y (b) impide de verdad que la pulsación llegue al sistema.
//
// Se auto-termina a los 25 s para no dejar el dispositivo secuestrado si algo
// va mal. Ctrl-C también sirve.

import Foundation
import IOKit
import IOKit.hid

setvbuf(stdout, nil, _IONBF, 0)

let earPodsVendorID = 0x05AC
let earPodsProductID = 0x110B
let consumerPage = 0x0C
let playPauseUsage: UInt32 = 0x00CD
let seizeDuration: TimeInterval = 180

nonisolated(unsafe) var pressStartedAt: Date?

let inputCallback: IOHIDValueCallback = { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == consumerPage,
          IOHIDElementGetUsage(element) == playPauseUsage
    else { return }

    if IOHIDValueGetIntegerValue(value) == 1 {
        pressStartedAt = Date()
        print("  ▼ DOWN")
    } else {
        let held = pressStartedAt.map { Date().timeIntervalSince($0) * 1000 } ?? 0
        pressStartedAt = nil
        let classification = held >= 300 ? "MANTENER → dispararía Flow" : "TOQUE → reemitiría play/pause"
        print(String(format: "  ▲ UP   %.0f ms  ·  %@", held, classification))
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

// Matcheamos SOLO los EarPods por vid/pid. Secuestrar por usage page se llevaría
// por delante el teclado interno, que también publica elementos Consumer.
IOHIDManagerSetDeviceMatching(
    manager,
    [
        kIOHIDVendorIDKey: earPodsVendorID,
        kIOHIDProductIDKey: earPodsProductID,
    ] as CFDictionary
)

IOHIDManagerRegisterInputValueCallback(manager, inputCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
guard openResult == kIOReturnSuccess else {
    print("FALLO: seize denegado, IOHIDManagerOpen = 0x\(String(openResult, radix: 16))")
    exit(1)
}

let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
print("SEIZE concedido sobre \(matched.count) dispositivo(s).")
print("""

Pon música sonando y pulsa el botón varias veces (toques y mantenidos).
  · Si la música NO se pausa  → el seize funciona, evento interceptado.
  · Si la música SÍ se pausa  → el seize no bloquea, hay que replantear.
Auto-termina en \(Int(seizeDuration)) s.

""")

Timer.scheduledTimer(withTimeInterval: seizeDuration, repeats: false) { _ in
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
    print("\nSeize liberado. Dispositivo devuelto al sistema.")
    exit(0)
}

CFRunLoopRun()
