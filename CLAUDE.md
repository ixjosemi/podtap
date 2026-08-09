# PodTap

Remaps the USB-C EarPods remote button to a configurable key, keeping
play/pause on a short tap.

## Hardware facts, already verified

Do not re-investigate these. Measured on real USB-C EarPods, macOS 26.5:

- Device: `vid=0x05AC pid=0x110B`, USB transport. Publishes **two** interfaces
  under the same vid/pid: Consumer Page (`0x0C`) and a vendor-defined one
  (`0xFF00`).
- The button emits usage `PlayPause` (`0x00CD`) with genuine 1/0 transitions —
  that is, with **press duration**. macOS collapses the pair into a toggle
  higher up; at the HID layer the information is intact.
- There is a virtual `Headset` device (transport `Audio`, also Consumer Page)
  that **emits nothing** for this button. Irrelevant to the project.
- Double and triple presses do **not** produce distinct usages: they are
  repeated DOWN/UP pairs separated by 109-171 ms.
- Measured durations: taps 79-231 ms (median ~111 ms), holds 1774-1947 ms.
- `kIOHIDOptionsTypeSeizeDevice` is granted and **genuinely blocks**: with music
  playing, 17 presses produced no pause.

## Design decisions

- **Short tap re-emits play/pause, hold sends the configured key.** Play/pause
  is decided on release, so it is delayed only by the length of the tap itself.
- **Dictation starts when the threshold is crossed, not on release.** That is
  what makes it real push-to-talk.
- **The output key is configurable from v1.** The app assumes nothing about
  Wispr Flow or any other specific app.
- **Wired EarPods only.** AirPods arrive over Bluetooth AVRCP, expose no HID
  device of their own, and cannot be seized this way. Out of scope.
- **Input via pure HID, no undocumented API.** The sole exception is *output*:
  re-emitting play/pause requires `NSEvent.systemDefined` with the magic
  `0xa00`/`0xb00` flags. That fragility is confined to `KeyOutput`.
- **Never in the Dock.** `LSUIElement` is set. The menu bar icon is optional;
  with it hidden, reopening the app from Finder is the way back to settings,
  handled via `applicationShouldHandleReopen`.
- **Permissions are front-loaded into a setup window**, not buried in settings.
  Without them the app silently does nothing, which is the worst failure mode.

## Conventions

- Everything user-facing and every source comment is in **English**.
- `GestureCore` imports neither IOKit nor CoreGraphics and takes its clock by
  injection. All decision logic lives there so it can be tested without
  hardware.
- Tests live in `tests/`, not `Tests/`. Paths are declared explicitly in
  `Package.swift`.
- Test helpers cannot be named `release`: it collides with the `NSObject`
  method `XCTestCase` inherits. Use `down`/`up`.
- Targets touching IOKit/AppKit build in Swift 5 language mode; `GestureCore`
  stays on Swift 6.

## Environment

Xcode is installed but `xcode-select` points at the Command Line Tools, which
ship no XCTest. For tests:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`Scripts/build-app.sh` handles this automatically.

## Packaging

- `Scripts/make-icon.sh` renders `Design/icon.svg` into `AppIcon.icns`. There is
  no SVG rasteriser in a stock macOS install, so it goes through `qlmanage`
  (WebKit) for the 1024px master, then `sips` and `iconutil`.
- `Scripts/build-app.sh` assembles the `.app` that SwiftPM cannot produce.
- `Scripts/build-dmg.sh` produces the drag-to-install disk image.

The ad-hoc signature matters: without any signature macOS will not reliably
grant Accessibility. But its `cdhash` changes on every build, so **permissions
must be re-granted after each rebuild**. Notarisation with a stable identity
will fix this.

## Status

- [x] `GestureCore`: `handle`, `tick`, `interrupt`. 13 tests.
- [x] `KeyOutput`: `KeyCombination`, `KeyEmitter`. 5 tests.
- [x] `HIDInput`: exclusive seize of the Consumer interface, hotplug.
- [x] `PodTapApp`: menu bar, settings, key recorder, first-run setup flow.
- [x] Icon and README hero as SVG; `.icns`, `.app` and `.dmg` pipelines.
- [ ] End-to-end verification on hardware with permissions granted.
- [ ] Launch at login (`SMAppService`).
- [ ] Notarisation, CI workflow, release with attached binary.
