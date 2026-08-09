# PodTap

Turns the USB-C EarPods remote button into a dictation toggle: one press holds
a configurable key down, the next lets it go. Play/pause is deliberately not
forwarded.

This file is loaded into every session, so it holds only what cannot be read
off the code: measurements not to repeat, and traps that each cost a day. The
README explains the product, and the scripts document their own mechanics at
the point of use.

## Measured, do not re-investigate

On real USB-C EarPods (`vid=0x05AC pid=0x110B`), macOS 26.5. Full numbers are
in the README; the diagnostic tools are in `tools/`.

- Two interfaces under the same vid/pid: Consumer Page (`0x0C`) and a
  vendor-defined `0xFF00`. The button is `PlayPause` (`0x00CD`) on the former,
  with genuine press and release transitions — macOS collapses them into a
  toggle higher up, but the information is intact underneath.
- `kIOHIDOptionsTypeSeizeDevice` is granted and genuinely blocks: 17 presses
  with music playing, no pause.
- Double and triple presses produce **no distinct usages**, only repeated
  DOWN/UP pairs 109–171 ms apart. Do not try to detect them.
- **Holding the button mutes the microphone.** 88 200 consecutive samples of
  exact digital silence while held, against 66 137 non-zero either side. The
  remote is read through the mic line, so while a button is down that line is
  not carrying audio. Nothing in software changes this — the recording was made
  by an unrelated process.

That last one is why the interaction is a toggle. Dictation has to happen with
the button **free**, so the classifier holds the key from one press to the next
instead of following the button. The dictation app still sees one long press
and needs no toggle mode of its own.

## Shortcut model

A `KeyCombination` is **modifiers plus an optional key**, not the reverse.
`⌘S` arrives as a `keyDown` carrying its modifiers, but `⌃⇧`, `⌥⇧` and Globe
produce no key event at all — only `flagsChanged`. A recorder listening to
`keyDown` cannot see them. Fn is a modifier (`maskSecondaryFn`), never a key
code.

- **Fn never reaches an application.** Measured with simultaneous taps at all
  three locations: Fn is visible at `.cghidEventTap` and `.cgSessionEventTap`
  and gone by `.cgAnnotatedSessionEventTap`, the last stop before delivery. So
  `NSEvent` monitors can never see it, and recording must happen at the HID
  tap. That tap **consumes** what it captures, so recording ⌘Q does not quit.
- **Modifiers are released one at a time**, so the last non-zero report is a
  subset of what was held — `⌘⇧` reports `⌘` on the way down. Accumulate the
  union across the press. Trusting the latest report saved `⌘⇧` as `⌘`.
- The Fn flag is **stripped from key combinations**: macOS sets it by itself on
  arrow, page and function keys, so `←` would be indistinguishable from `🌐←`.
  Globe alone is unaffected, being modifier-only.
- Caps Lock is excluded: it latches, so it cannot be held.

Emitting a modifier-only combination means one transition per modifier,
accumulating flags, released in reverse.

## Design decisions

- **The button is a dictation toggle and nothing else.** The device is seized,
  the press is never forwarded, nothing re-emits play/pause.
- **Nothing measures time.** No threshold, no timer, no duration comparison
  anywhere in the gesture path. The hardware already made that decision for us.
- `GestureClassifier` tracks the button's own position (`opening`, `closing`)
  only so device chatter — two presses with no release between — cannot read as
  a second gesture.
- **No undocumented API anywhere.** There used to be exactly one: re-emitting
  play/pause needs `NSEvent.systemDefined` with magic `0xa00`/`0xb00` flags.
  Dropping play/pause deleted it. Do not reintroduce it without saying so — it
  was the project's only fragility against an OS update.
- **Wired EarPods only.** AirPods arrive over Bluetooth AVRCP, expose no HID
  device, and cannot be seized this way.
- **Permissions are front-loaded into a setup window.** Without them the app
  silently does nothing, which is the worst possible failure mode.

## Interface

**Two layers of glass, and the order is not optional.** `WindowBackdrop`
(`NSVisualEffectView`) is the only thing that can sample the desktop; SwiftUI's
materials blur what is behind them *inside* the window, which over an opaque
window is nothing. It only works because `HostedWindowController` sets
`isOpaque = false` and a clear `backgroundColor`. Every window needs its own
backdrop — one without is not unstyled, it is see-through.

**The settings window must always offer Quit.** `LSUIElement` means no Dock
tile, no app menu, no menu bar of PodTap's own, so with the icon hidden there
is otherwise no way out. `killall` is not a substitute: SIGTERM skips
`applicationWillTerminate`, where the held key is released, so a force-quit can
leave the key down system-wide. Do not remove that button for minimalism.

**Do not use SwiftUI's `Settings` scene.** In an accessory app it silently does
nothing — `sendAction(showSettingsWindow:)` returns `true` and no window is
created. Accessory apps are also outside the activation chain, so showing a
window needs `NSApp.activate` as well as `makeKeyAndOrderFront`.
`applicationShouldHandleReopen` is the only route back in when the icon is
hidden.

Two rules keep the window sparse: nothing explains itself in prose (setup is
where PodTap teaches; reasons live in tooltips), and permissions only appear
while they are missing.

`AppStatus` in `GestureCore` is the single source for "what is PodTap doing" —
menu bar symbol and settings indicator both derive from it, so they cannot
drift. It is pure, so its state precedence is tested.

## Permissions

- **`IOHIDCheckAccess` lies after a live grant.** It answers from a per-process
  cache, so an app already running when the user ticks Input Monitoring reports
  denial for as long as it lives while the next `IOHIDManagerOpen` succeeds.
  Trust `isReadingDevice` instead, and offer **Quit & Reopen**, the only thing
  that clears it. `AXIsProcessTrusted()` has no such problem.
- **A rebuild does not necessarily invalidate a grant.** Measured: the cdhash
  changed and both permissions stayed in effect. Do not treat a lost permission
  as the cost of rebuilding — find the real cause.
- **Duplicate TCC records are the real trap.** Two decisions for one bundle id
  make System Settings show the app ticked while it is denied, and asking
  raises *no dialog at all*. Toggling the switch flips the stale record rather
  than replacing it, so it is unrecoverable from the interface — which is why
  `request()` runs `tccutil reset` first. Duplicates come from two copies on
  disk, or from launching the binary from a shell, which records the grant
  against the terminal. Test through `open -a` or Finder, and keep exactly one
  copy, in `/Applications`.

The signing identity is what decides whether a grant survives a rebuild at all,
and a **revoked** certificate is worse than none — macOS treats it as malware.
`build-app.sh` guards against that after signing; the reasoning is in the script
and in the README under *Keeping permissions across rebuilds*.

## Conventions

- Everything user-facing and every source comment is in **English**.
- `GestureCore` imports neither IOKit nor CoreGraphics and reads no clock. All
  decision logic lives there so it can be tested without hardware.
- Tests live in `tests/`, not `Tests/`, declared explicitly in `Package.swift`.
- Test helpers cannot be named `release` — it collides with the `NSObject`
  method `XCTestCase` inherits. Use `down`/`up`.
- IOKit/AppKit targets build in Swift 5 mode; `GestureCore` stays on Swift 6.
- `xcode-select` points at the Command Line Tools, which ship no XCTest:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
  `build-app.sh` handles this itself.

## Packaging

`Scripts/` holds icon, DMG background, DMG layout, `.app` and `.dmg` builds.
Each script documents its own mechanics; read the one you are changing.

`Resources/AppIcon.icns`, `Design/dmg-background.tiff` and `Design/dmg-DS_Store`
are **committed artefacts**, generated locally and never built in CI: they need
a window server and Finder automation that runners do not have. Regenerate and
commit whenever the corresponding source changes.

`qlmanage` is the only SVG rasteriser on a stock macOS, and it has two quirks
worth knowing before trusting its output: it renders onto an **opaque white**
canvas, so a "transparent" PNG used as a template image paints a filled square;
and it fits to height and crops width, so non-square art has to be padded to a
square and cropped back.

## Releases

CI runs tests and builds the DMG on every commit, so a release is never the
first time the packaging path runs. `release.yml` builds the universal binary —
runners are Apple Silicon, and arm64-only would not launch on Intel — and
attaches it to the GitHub release, idempotently, since tag push and release
publish can both fire for the same version.

**`VERSION` at the repo root is the only place the version is written down.**
Cut a release by editing it, committing, then tagging to match. The workflow
refuses to build when the tag and the file disagree, rather than publishing a
release whose bundle calls itself something else.
