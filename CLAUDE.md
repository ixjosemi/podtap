# PodTap

Turns the USB-C EarPods remote button into a dictation toggle: one press holds
a configurable key down, the next lets it go. Play/pause is deliberately not
forwarded.

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

### Holding the button mutes the microphone

The single most important fact about this hardware, and it kills push-to-talk
outright. Recorded from `EarPods Microphone` while speaking continuously for
nine seconds, holding the button only for the middle three:

```
0.75 – 2.75 s   button free     −25 dB
3.75 – 6.00 s   BUTTON HELD     −99 dB   88 200 samples, every one exactly 0
6.25 – 8.00 s   button free     −17 dB
```

Not attenuation — digital silence, maximum absolute sample value 0, against
66 137 of 66 150 non-zero samples either side. The remote is read through the
microphone line, the same resistor-ladder trick the analogue EarPods use, so
while a button is down that line is not carrying audio.

Nothing in software can change this. It is not the HID seize either: the
recording above was taken by an unrelated process.

The consequence is the whole interaction model. Dictation must happen with the
button **free**, so `GestureClassifier` holds the key down from one press to the
next rather than tracking the button. The dictation app still sees one long key
press and needs no toggle mode.

## Shortcut model

A `KeyCombination` is **modifiers plus an optional key**, not a key plus
modifiers. That shape is forced by how macOS reports input:

- `⌘S` arrives as a `keyDown` carrying its modifiers.
- `⌃⇧`, `⌥⇧` and Globe/Fn produce **no key event at all** — only
  `flagsChanged` transitions. A recorder listening solely to `keyDown` cannot
  see them, which is exactly the bug that made Fn look unmappable.

Fn is a modifier (`maskSecondaryFn`), not a key. Treating it as a key code was
a false start.

### Fn never reaches an application

Recording has to happen in a `CGEventTap` at `.cghidEventTap`. An `NSEvent`
monitor cannot see the Globe key at all. Measured with listen-only taps at all
three locations simultaneously, posting one synthetic Fn transition:

```
Fn       → HID ✓   SESSION ✓   ANNOTATED ✗
Control  → HID ✓   SESSION ✓   ANNOTATED ✓
```

`.cgAnnotatedSessionEventTap` is the last stop before application delivery, so
anything invisible there is invisible to `NSEvent`. Something between the
session tap and the app absorbs Fn specifically. That, not the shortcut model,
is why Globe looked unmappable through two separate fixes.

The recorder tap **consumes** what it captures, so recording ⌘Q does not quit
PodTap and recording Globe does not fire the dictation app being mapped.
Verified: 6 posted transitions, 6 seen by the tap, 0 escaping downstream.

Modifiers are released **one at a time**, so the last non-zero report is a
subset of what was held — `⌘⇧` reports `⌘` on the way down to nothing. The
recorder accumulates the union of everything seen during the press. Trusting
the latest report saved `⌘⇧` as `⌘`.

The Fn flag is stripped from key combinations. macOS sets it by itself on
arrow, page and function keys, so `←` is indistinguishable from `🌐←`. Globe
alone is unaffected: it is a modifier-only combination.

### Wispr Flow responds to the synthesised Globe

Observed while probing: a synthetic Fn down/up pair made Wispr Flow run its
dictation cycle and paste, which showed up on the taps as an unsolicited `⌘V`.
The output path is confirmed against a real consumer.

Emitting a modifier-only combination means sending **one transition per
modifier**, accumulating flags, and releasing in reverse. Verified against a
listening event tap:

```
hold ⌃⇧   → keyCode=59 [control] → keyCode=56 [control+shift]
release   → keyCode=56 [control] → keyCode=59 [none]
```

Caps Lock is excluded on purpose: it latches, so it cannot be held.

## Design decisions

- **The button is a dictation toggle and nothing else.** One press holds the
  key down, the next lets it go. Play/pause is deliberately gone: the device is
  seized, the press is never forwarded, and nothing re-emits it.
- **Nothing measures time.** There is no threshold, no timer and no duration
  comparison anywhere in the gesture path. Press duration was the axis of the
  old design; keeping it would only reintroduce a decision the hardware already
  made for us.
- **`GestureClassifier` tracks the button's own position** (`opening`,
  `closing`) purely so device chatter — two presses with no release between —
  cannot read as a second gesture. It is the only failure mode left in a
  four-state machine.
- **The output key is configurable from v1.** The app assumes nothing about
  Wispr Flow or any other specific app.
- **Wired EarPods only.** AirPods arrive over Bluetooth AVRCP, expose no HID
  device of their own, and cannot be seized this way. Out of scope.
- **No undocumented API anywhere.** There used to be exactly one: re-emitting
  play/pause needs `NSEvent.systemDefined` with magic `0xa00`/`0xb00` flags.
  Dropping play/pause deleted it. Do not reintroduce that code to bring the
  feature back without saying so explicitly — it was the project's only
  fragility against an OS update.
- **Never in the Dock.** `LSUIElement` is set. The menu bar icon is optional;
  with it hidden, reopening the app from Finder is the way back to settings,
  handled via `applicationShouldHandleReopen`.
- **Permissions are front-loaded into a setup window**, not buried in settings.
  Without them the app silently does nothing, which is the worst failure mode.

## Interface

Two layers of glass, and the order is not optional. `WindowBackdrop`
(`NSVisualEffectView`, `.underWindowBackground`, `.behindWindow`) is the only
thing that can sample the desktop; SwiftUI's own materials blur what is behind
them *inside* the window, which over an opaque window means blurring nothing.
It only works because `HostedWindowController` sets `isOpaque = false` and a
clear `backgroundColor` — without both, AppKit paints over it and the result is
a flat grey rectangle. Cards then use `.ultraThinMaterial` on top of that
backdrop, which is where the depth comes from.

Every window therefore needs a `WindowBackdrop` of its own. A hosted view
without one is not merely unstyled, it is see-through.

The settings window is a header over named sections of grouped rows, which is
the shape of a System Settings pane. Earlier attempts floated shadowed cards
with a white gradient rim — the house style of every glassmorphism template
going, and it read as exactly that. The vibrancy does the work; a box only has
to group the rows sitting on it. The header is washed with
`Color.accentColor`, so it picks up whatever accent the Mac is set to rather
than a colour PodTap invented.

Two more rules keep the window sparse:

- **Nothing explains itself in prose.** The setup flow is where PodTap teaches.
  A caption under every group turned the window into a leaflet — the reason a
  permission is wanted lives in a `.help` tooltip instead.
- **Permissions only appear while they are missing.** Two rows reading
  "Granted" are noise for the entire life of the app. Once they are in effect
  the group disappears; the status pill is what says everything is fine.

`Resources/GitHubMark.png` is GitHub's own mark (Octicons, MIT), committed
rather than rendered at build time for the same reason as the app icon. Note
for regenerating it: `qlmanage` rasterises SVG onto an **opaque white** canvas,
so its output used as a template image paints a filled grey square. The
committed file was rebuilt as a real mask, taking alpha from pixel darkness,
which for a black-on-white glyph reproduces the coverage exactly.

**The settings window must always offer Quit.** `LSUIElement` means no Dock
tile, no application menu and no menu bar of PodTap's own, so with the menu bar
icon hidden there is otherwise no way out of the app at all. Activity Monitor
and `killall` are not a substitute: SIGTERM skips `applicationWillTerminate`,
which is where the held key is released and the device handed back, so a
force-quit can leave the configured key down system-wide with nothing left
running to lift it. Do not remove that button in the name of minimalism.

`AppStatus` in `GestureCore` is the single source for "what is PodTap doing" —
the menu bar symbol and the settings pill both derive from it, so they cannot
drift apart. It is pure, so the precedence between its states is tested.

## Windows

**Do not use SwiftUI's `Settings` scene.** In an accessory app it silently does
nothing: `NSApp.sendAction(Selector(("showSettingsWindow:")))` returns `true`
and no window is ever created. Reporting success while doing nothing is worse
than failing, and it cost a debugging session.

Both settings and setup go through `HostedWindowController`, which owns a real
`NSWindow` wrapping an `NSHostingView`. An accessory app is also outside the
activation chain, so showing a window requires `NSApp.activate` as well as
`makeKeyAndOrderFront` — otherwise it appears behind whatever the user is doing.

`applicationShouldHandleReopen` is the only route back into the app when the
menu bar icon is hidden. Spotlight, Raycast and Finder all arrive there. It was
verified to fire correctly; the bug was purely that the window it asked for was
never created.

## Conventions

- Everything user-facing and every source comment is in **English**.
- `GestureCore` imports neither IOKit nor CoreGraphics, and reads no clock at
  all. All decision logic lives there so it can be tested without hardware.
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
- `Scripts/make-dmg-background.sh` renders `Design/dmg-background.svg` into a
  multi-representation `dmg-background.tiff` (1x and 2x).
- `Scripts/make-dmg-layout.sh` drives Finder over AppleScript to arrange the
  installer window, then extracts the resulting `Design/dmg-DS_Store`.
- `Scripts/build-app.sh` assembles the `.app` that SwiftPM cannot produce.
- `Scripts/build-dmg.sh` produces the drag-to-install disk image.

### Three committed artefacts, and why

`Resources/AppIcon.icns`, `Design/dmg-background.tiff` and `Design/dmg-DS_Store`
are all generated locally and committed, never built in CI. Each needs something
a runner does not have: `qlmanage` needs a window server, and arranging the
installer window needs Finder automation. Baking them on a real desktop keeps
release builds fully headless and deterministic.

Regenerate and commit whenever the corresponding SVG or window design changes.

Two traps worth remembering:

- The DMG **volume name must stay `PodTap`**, with no version. `.DS_Store`
  records the background image by path inside the volume, so a versioned name
  would break the layout on every release.
- Finder's `bounds` includes the title bar. Asking for exactly the background
  height crops the bottom of the image, so the layout script pads by 28 points.

`Resources/AppIcon.icns` is a **committed artefact**, not a build output.
Rendering it needs `qlmanage`, which needs a window server session that CI
runners cannot be relied on to have. Re-run `make-icon.sh` and commit the result
whenever the SVG changes.

Release builds set `UNIVERSAL=1` so the binary carries both arm64 and x86_64.
CI runners are Apple Silicon, and an arm64-only build simply would not launch on
an Intel Mac.

### Signing identity

`build-app.sh` signs with a real certificate when one is available, and falls
back to ad-hoc otherwise. This is not cosmetic — it decides whether permissions
survive a rebuild:

```
ad-hoc      designated => cdhash H"918bb4bc…"
certificate designated => identifier "com.github.ixjosemi.podtap"
                          and anchor apple generic
                          and certificate leaf[subject.CN] = "Apple Development: …"
```

The ad-hoc requirement is pinned to the binary's content, so every rebuild
looks like a different app to TCC. The certificate requirement is pinned to the
bundle identifier and the certificate, and stays byte-identical across builds —
verified by building twice with different content and diffing the requirement.

Any **valid** code signing certificate works, including a free **Apple
Development** identity created by Xcode with a plain Apple ID. No paid
membership needed. Set `PODTAP_SIGNING_IDENTITY` to choose explicitly; a single
available identity is picked automatically.

#### A revoked certificate is worse than none

Signing with a revoked certificate makes macOS classify the app as **malware**:
XProtect blocks it and deletes it, because revocation is exactly how Apple
kills known-bad software. This happened during development and cost an install.

The trap is that `security find-identity -v -p codesigning` lists a revoked
certificate as valid. Revocation is checked online at assessment time, so the
keychain genuinely does not know. The only reliable test is:

```sh
spctl --assess --type execute -vvv build/PodTap.app   # CSSMERR_TP_CERT_REVOKED
syspolicy_check distribution build/PodTap.app         # spells it out in English
```

`build-app.sh` runs that check after signing and falls back to ad-hoc if the
certificate turns out to be revoked. Never remove that guard.

CI has no identity and signs ad-hoc, which is correct: the private key must not
leave the developer's keychain, and a certificate that downloaders do not trust
would add nothing anyway.

### `IOHIDCheckAccess` lies after a live grant

It answers from a cache filled once per process. An app that was already
running when the user ticked Input Monitoring keeps reporting denial for as
long as it lives, while the very next `IOHIDManagerOpen` succeeds. Confirmed on
a live install: PodTap held the EarPods exclusively — an outside probe got
`kIOReturnExclusiveAccess` and `ioreg -c IOHIDLibUserClient` named PodTap as
the owner — while its own interface showed the permission missing.

So the interface trusts `EarPodsButtonMonitor.isReadingDevice`, meaning the
device is open **and** present, and falls back to `IOHIDCheckAccess` only when
there is nothing plugged in to prove it either way. A **Quit & Reopen** button
is offered alongside, since restarting is the only thing that clears the cache.

Accessibility has no such problem: `AXIsProcessTrusted()` is evaluated live.

### The TCC trap

Without any signature macOS will not reliably grant Accessibility at all. TCC
keys permissions on **path plus code requirement**, and with an ad-hoc signature
that requirement embeds a `cdhash` which changes on every build.

**A rebuild does not necessarily invalidate a grant.** An earlier version of
this file claimed it always does; measured on macOS 26.5, it does not. Replacing
`/Applications/PodTap.app` in place took the cdhash from `8c69bdc1…` to
`0cbc3328…`, and both permissions stayed in effect — Accessibility still read as
trusted, and the seize still succeeded. Do not treat a lost permission as the
expected cost of rebuilding; go and find the actual cause.

What genuinely breaks is **duplicate records**. TCC can end up holding more than
one decision for the same bundle identifier — a copy launched from a shell, or
from `build/`, records against a different identity. Then:

- System Settings lists PodTap ticked, while the app is denied.
- Asking for the permission raises **no dialog at all**, because as far as TCC
  is concerned the question was already answered.
- Toggling the switch does not help: it flips the stale record rather than
  replacing it.

That combination is unrecoverable from the interface, which is why `request()`
runs `tccutil reset` for its own bundle identifier first. It is safe there
because the interface only offers the request when the permission is not in
effect. The number of "Successfully reset" lines `tccutil` prints is the number
of stale identities that had accumulated — it printed **two** when this was
diagnosed.

Still true, and still the cause of those duplicates:

- Two copies of the app on disk are two distinct identities. Keep exactly one,
  in `/Applications`.
- Launching the binary from a shell makes the **terminal** the responsible
  process, so the grant is recorded against the wrong app. Always launch through
  LaunchServices (`open -a`) or Finder when testing permissions.

A stable signing identity (self-signed certificate, or Developer ID) would make
the requirement pin to the certificate rather than the hash, removing the
question entirely.

## Releases

`.github/workflows/ci.yml` runs the tests and builds the DMG on every commit, so
a release is never the first time the packaging path is exercised.

`.github/workflows/release.yml` builds the universal DMG and attaches it to the
GitHub release. It fires on a `v*` tag, on a published release, or manually. The
publish step is idempotent because tag push and release publish can both fire
for the same version.

**The `VERSION` file at the repo root is the only place the version is written
down.** Both build scripts read it; nothing takes it as an argument any more.
It used to default to a hardcoded `0.1.0` in `build-app.sh`, which meant every
locally built bundle claimed to be 0.1.0 no matter what was in it — only CI,
passing the tag in, ever produced an honest one.

Cut a release by editing `VERSION`, committing, then
`git tag v0.3.1 && git push origin v0.3.1`. The workflow refuses to build when
the tag and the file disagree, rather than publishing a `v0.3.1` release
containing a bundle that calls itself something else.

## Status

- [x] `GestureCore`: `handle`, `interrupt`. 14 tests, no clock involved.
- [x] `KeyOutput`: `KeyCombination`, `KeyEmitter`, `ShortcutRecording`. 28 tests.
- [x] `HIDInput`: exclusive seize of the Consumer interface, hotplug.
- [x] `PodTapApp`: menu bar, settings, key recorder, first-run setup flow.
- [x] End-to-end on hardware: Globe recorded, key held across a dictation,
      Wispr Flow driven from the remote.
- [x] Icon and README hero as SVG; `.icns`, `.app` and `.dmg` pipelines.
- [ ] Launch at login (`SMAppService`).
- [ ] Notarisation, CI workflow, release with attached binary.
