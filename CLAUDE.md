# PodTap

Remapea el botón del mando de los EarPods USB-C a una tecla configurable,
conservando el play/pause en el toque corto.

## Hechos verificados sobre hardware

No re-investigar esto, ya está medido sobre EarPods USB-C reales en macOS 26.5:

- Dispositivo: `vid=0x05AC pid=0x110B`, transport USB. Expone **dos** interfaces
  bajo el mismo vid/pid: Consumer Page (`0x0C`) y una vendor-defined (`0xFF00`).
- El botón emite usage `PlayPause` (`0x00CD`) con transiciones reales 1/0, es
  decir con **duración de pulsación**. macOS colapsa ese par en un toggle en una
  capa superior; a nivel HID la información está completa.
- Existe un dispositivo virtual `Headset` (transport `Audio`, también Consumer
  Page) que **no emite nada** para este botón. Irrelevante para el proyecto.
- La doble y triple pulsación **no** generan usages distintos: son pares
  DOWN/UP repetidos, separados por 109-171 ms.
- Duraciones medidas: toques 79-231 ms (mediana ~111 ms), mantenidos
  1774-1947 ms.
- `kIOHIDOptionsTypeSeizeDevice` se concede y **bloquea de verdad**: con música
  sonando, 17 pulsaciones no produjeron ninguna pausa.

## Decisiones de diseño

- **Toque corto = play/pause reemitido, mantener = tecla configurable.** El
  play/pause se decide al soltar, así que solo se retrasa lo que dure el toque.
- **El dictado arranca al cruzar el umbral, no al soltar.** Es lo que hace que
  sea push-to-talk real.
- **La tecla de salida es configurable desde v1.** La app no asume nada sobre
  Wispr Flow ni sobre ninguna otra app concreta.
- **Solo EarPods con cable.** Los AirPods llegan por AVRCP sobre Bluetooth, no
  exponen HID propio y no se pueden secuestrar así. Fuera de alcance.
- **Entrada por HID puro, sin APIs no documentadas.** La única excepción es la
  *salida*: reemitir play/pause obliga a usar `NSEvent.systemDefined` con los
  flags mágicos `0xa00`/`0xb00`. Esa fragilidad queda confinada a `KeyOutput`.

## Convenciones

- `GestureCore` no importa IOKit ni CoreGraphics y recibe el tiempo inyectado.
  Cualquier lógica de decisión vive ahí para poder testearse sin hardware.
- Tests en `tests/`, no en `Tests/`. Las rutas están declaradas explícitamente
  en `Package.swift`.
- Los helpers de test no pueden llamarse `release`: colisiona con el método de
  `NSObject` que hereda `XCTestCase`. Se usan `down`/`up`.

## Entorno

Xcode está instalado pero `xcode-select` apunta a Command Line Tools, que no
traen XCTest. Para los tests:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Estado

- [x] `GestureCore`: tipos, `tick`, `interrupt`, suite de 13 tests.
- [ ] `GestureCore.handle(_:)` — pendiente.
- [ ] `HIDInput`: IOHIDManager, seize, hotplug, liberar la tecla al desconectar.
- [ ] `KeyOutput`: síntesis de tecla configurable y de play/pause.
- [ ] `App`: barra de menús, preferencias, onboarding de permisos
      (Monitorización de entrada + Accesibilidad).
- [ ] Empaquetado `.app` con `LSUIElement` y script de release.
