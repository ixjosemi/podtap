# PodTap

Convierte el botón del mando de los EarPods USB-C de Apple en una tecla
configurable de macOS, conservando el play/pause.

- **Toque corto** → play/pause, como siempre.
- **Mantener** → mantiene pulsada la tecla que configures, y la suelta al
  soltar el botón.

El caso de uso original es el dictado por voz: apps como Wispr Flow, Superwhisper
o el dictado nativo funcionan con *push-to-talk*, y mantener un botón del cable
es más cómodo que buscar una tecla.

> **Estado: en construcción.** La viabilidad técnica está verificada sobre
> hardware real (ver abajo), pero la app todavía no es utilizable.

## Por qué existe

No había forma de hacer esto. El
[issue #2398 de Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements/issues/2398)
lleva años abierto pidiendo exactamente esta funcionalidad. Las apps existentes
del ecosistema —[MediaKeyTap](https://github.com/the0neyouseek/MediaKeyTap),
[mac-media-keys](https://github.com/rayhatfield/mac-media-keys),
[mac-bt-headset-fix](https://github.com/jguice/mac-bt-headset-fix)— reenvían las
media keys a un reproductor, pero ninguna permite remapear el botón a una tecla
arbitraria.

## Cómo funciona

macOS presenta el botón como un toggle de play/pause, pero eso es una pérdida de
información introducida en una capa alta. Por debajo, los EarPods USB-C son un
dispositivo HID normal que publica en la Consumer Page (`0x0C`) el usage
`PlayPause` (`0x00CD`) con transiciones reales de valor 1/0.

PodTap abre ese dispositivo con `kIOHIDOptionsTypeSeizeDevice`, lo que impide
que el evento llegue al sistema, y decide qué hacer según cuánto dure la
pulsación. Como el evento original ya no existe, el play/pause del toque corto
se sintetiza de vuelta.

### Mediciones sobre hardware real

Tomadas con los spikes de diagnóstico, sobre EarPods USB-C
(`vid=0x05AC pid=0x110B`) en macOS 26.5:

| | n | rango | mediana |
|---|---|---|---|
| Toques | 15 | 79 – 231 ms | ~111 ms |
| Mantenidos | 2 | 1774 – 1947 ms | — |

El hueco entre ambos grupos es lo bastante amplio como para que un umbral de
300 ms clasifique correctamente. Verificado además que el *seize* bloquea de
verdad: con música sonando, 17 pulsaciones no produjeron ni una pausa.

## Arquitectura

```
Sources/
  GestureCore/    Lógica pura de clasificación. Sin IOKit ni CoreGraphics.
  HIDInput/       IOHIDManager, seize, hotplug.            (pendiente)
  KeyOutput/      Síntesis de CGEvent y play/pause.        (pendiente)
  App/            Barra de menús, preferencias, permisos.  (pendiente)
tests/
  GestureCoreTests/
```

`GestureCore` no tiene dependencias del sistema y recibe el tiempo inyectado, así
que toda la máquina de estados se testea sin hardware ni relojes reales.

## Desarrollo

```sh
swift build
swift test
```

Si `swift test` falla con `no such module 'XCTest'`, tu `xcode-select` apunta a
Command Line Tools en vez de a Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Alcance

Solo **EarPods USB-C con cable**. Los AirPods quedan fuera a propósito: llegan
por AVRCP sobre Bluetooth, no exponen un dispositivo HID propio y no se pueden
secuestrar por esta vía.

## Licencia

MIT.
