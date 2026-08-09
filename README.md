<p align="center">
  <img src="Design/hero.svg" alt="PodTap — turn the EarPods remote button into any macOS key" width="100%">
</p>

<p align="center">
  <a href="https://github.com/ixjosemi/podtap/releases"><img alt="Release" src="https://img.shields.io/github/v/release/ixjosemi/podtap?style=flat-square&color=7C3AED"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-4F46E5?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-DB2777?style=flat-square">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-22D3EE?style=flat-square"></a>
</p>

# PodTap

**PodTap turns the button on your wired Apple EarPods into a dictation switch:
press to start talking, press again to stop.**

The button stops being a play/pause button and becomes the key of your choice,
held down for exactly as long as you are speaking.

It works with Wispr Flow, Superwhisper, macOS Dictation, Discord, Slack huddles,
or anything else driven by a held key — no toggle mode required at the other
end, because as far as those apps are concerned the key really is held down the
whole time.

Everything is configured in the app. There is no config file, no scripting, and
nothing to compile.

---

## How you use it

```
      press ──────────▶ talk ──────────▶ press
        │                                  │
        │      button free, and this is    │
        │      the only part that records  │
        │                                  │
   your key DOWN ═══════════════════ your key UP
```

**Press** the button once. PodTap presses your key and leaves it down; the menu
bar icon turns into a waveform so you can see it took.

**Talk**, for as long as you like, with the button free. Your dictation app sees
an ordinary key being held, exactly as if your finger were on it.

**Press** again to finish. The key comes up and dictation ends.

That is the whole interaction. There is no hold, no threshold, and no timing to
get right — press duration is not measured at all.

> **Play/pause is gone, deliberately.** PodTap takes the device exclusively, so
> the press never reaches macOS and never controls playback. The button belongs
> to dictation now. If you want play/pause back, quit PodTap and the button
> returns to normal instantly.

### Why the key is held by PodTap and not by your thumb

Because the EarPods will not let you hold. **The remote button mutes the
microphone for as long as it is pressed**, and it is not subtle about it.

Recorded from the EarPods microphone during nine seconds of continuous speech,
with the button held only for the middle three:

```
0.75 – 2.75 s   button free     −25 dB   ███████████████
3.75 – 6.00 s   BUTTON HELD     −99 dB
6.25 – 8.00 s   button free     −17 dB   ███████████████
```

That is not a quiet signal. Across those two seconds every one of **88 200
samples is exactly zero**, maximum absolute value 0 — against 66 137 non-zero
samples out of 66 150 either side. Digital silence, not attenuation.

The reason is in the hardware: the remote is read through the microphone line,
the same resistor-ladder trick the analogue EarPods use. While a button is down
that line is busy reporting the button, not carrying audio.

So push-to-talk is impossible on these headphones. The microphone is dead for
precisely as long as the gesture meant to be recording. No software can work
around it — the recording above was made by a process with no connection to
PodTap at all.

Hence one press to start and another to stop: PodTap holds the key so your thumb
does not have to, and your thumb stays off the microphone.

---

## Why this exists

There was no way to do this. The
[Karabiner-Elements issue asking for it](https://github.com/pqrs-org/Karabiner-Elements/issues/2398)
has been open for years with no resolution. Every existing tool in this space —
[MediaKeyTap](https://github.com/the0neyouseek/MediaKeyTap),
[mac-media-keys](https://github.com/rayhatfield/mac-media-keys),
[mac-bt-headset-fix](https://github.com/jguice/mac-bt-headset-fix) — forwards
media keys to a *player*. None of them let you remap the button to an arbitrary
key.

## Install

Download the latest `.dmg` from
[Releases](https://github.com/ixjosemi/podtap/releases) and drag PodTap to
Applications. Every release is built by GitHub Actions from a tagged commit, as
a universal binary that runs on both Apple Silicon and Intel.

PodTap is **not notarised** — that needs a paid Apple Developer account — so
macOS quarantines it on download. Clear that once:

```sh
xattr -dr com.apple.quarantine /Applications/PodTap.app
```

Skipping this step is the usual cause of macOS refusing to open the app, or
claiming it is damaged.

Then open PodTap from Finder. A setup window walks you through the two required
permissions and lets you pick your key. Nothing works until those permissions
are granted, so setup asks for them up front rather than failing silently
later.

### What you can map it to

| Kind | Examples |
|---|---|
| A plain key | `F13`, `F18` |
| A key with modifiers | `⌘S`, `⌃⌥Space` |
| Modifiers on their own | `⌃⇧`, `⌥⇧` |
| Globe / Fn | `🌐` — the default trigger in several dictation apps |

Modifier-only shortcuts and Globe produce no key event on macOS, only modifier
transitions, so PodTap emits them the same way real keys do: one transition per
modifier, released in reverse.

Recording them is the harder half. Globe never reaches an application's own
event stream at all — measured with taps at all three levels, it is visible to
the system and gone by the time it would be delivered — so PodTap captures
shortcuts one layer below, and swallows what it captures. Pressing ⌘Q into the
field records ⌘Q instead of quitting.

Caps Lock is not offered. It latches rather than being held, so PodTap cannot
keep it down for the length of a dictation.

| Permission | Why it is needed |
|---|---|
| **Input Monitoring** | To read the button on the EarPods remote. |
| **Accessibility** | To send the key you chose, and to record one in the first place. |

Input Monitoring only takes effect once PodTap restarts: macOS answers that
particular question from a cache filled when the app launched. If the switch is
already on and PodTap still says otherwise, use **Quit & Reopen** next to the
permission.

Then set the same key as the shortcut in your dictation app, and you are done.

### Build from source

```sh
git clone https://github.com/ixjosemi/podtap.git
cd podtap
./Scripts/build-app.sh          # produces build/PodTap.app
./Scripts/build-dmg.sh          # produces build/PodTap-<version>.dmg
```

## Where PodTap lives

PodTap never appears in the Dock or the app switcher. By default it sits in the
menu bar, where the icon reflects state at a glance: ready, recording, or no
EarPods connected.

If you would rather not see it at all, turn off **Show in menu bar** in Settings
and it becomes a pure background agent. Opening PodTap again from Finder brings
the settings window back, so hiding the icon is never a one-way door.

Quitting is in that window too, next to the version. With no Dock tile and no
menu bar of its own, PodTap would otherwise have no way out once the icon is
hidden — and force-quitting is not a substitute here: it skips the shutdown that
releases the key, which can leave it held down across the whole system.

## How it works

macOS presents the remote button as a play/pause toggle, but that is
information being thrown away higher up the stack. Underneath, USB-C EarPods are
an ordinary HID device publishing the `PlayPause` usage (`0x00CD`) on the
Consumer Page (`0x0C`), with genuine press and release transitions.

PodTap opens that device with `kIOHIDOptionsTypeSeizeDevice`, which stops the
event from reaching the system at all. That is what frees the button: macOS
never learns it was pressed, so nothing pauses, and PodTap is free to give the
press an entirely different meaning.

Seizing is not optional. macOS synthesises play/pause on button *down*, so a
`CGEventTap` would only ever see the aftermath — the music would already have
paused. Only intercepting below that layer is early enough.

Everything downstream is a four-state machine in
[`GestureCore`](Sources/GestureCore), which imports neither IOKit nor
CoreGraphics and can be replayed in a test as a plain sequence of events. It
measures nothing and holds no timers; the button's own position is tracked only
so that device chatter — two presses with no release between them — cannot be
mistaken for a second gesture.

### Measurements from real hardware

Captured on USB-C EarPods (`vid=0x05AC pid=0x110B`) running macOS 26.5, with the
diagnostic tools in [`tools/`](tools):

| | Result |
|---|---|
| Seizing genuinely blocks | 17 presses with music playing, not a single pause |
| Press durations | taps 79 – 231 ms, holds 1774 – 1947 ms |
| **Microphone while held** | **88 200 consecutive zero samples** |

The last one is the measurement that shaped the whole design — see
[why the key is held by PodTap](#why-the-key-is-held-by-podtap-and-not-by-your-thumb).
The press durations are recorded for completeness; nothing uses them any more,
because duration no longer distinguishes anything.

### What happens if something goes wrong

The key is held by PodTap, so it is PodTap's job to let go of it. Unplugging the
EarPods mid-dictation, quitting the app, or disabling it in Settings all lift the
key first. A held key is never left stranded down.

## Architecture

```
Sources/
  GestureCore/    Pure classification logic. No IOKit, no CoreGraphics.
  HIDInput/       IOHIDManager, exclusive seize, hotplug handling.
  KeyOutput/      CGEvent synthesis and shortcut recording.
  PodTapApp/      Menu bar, setup flow, settings, permissions.
tests/
  GestureCoreTests/
  KeyOutputTests/
tools/            Standalone HID probes used to derive the numbers above.
```

`GestureCore` has no system dependencies, so the entire state machine is tested
without hardware. The same goes for the trickier half of shortcut recording,
which lives in `KeyOutput` as a pure state machine and is exercised without a
keyboard.

**PodTap uses no undocumented API.** It did while the button still forwarded
play/pause, which has no public equivalent and needed `NSEvent.systemDefined`
with magic `0xa00`/`0xb00` flags. Dropping play/pause took that dependency with
it.

## Development

```sh
swift build
swift test
```

If `swift test` fails with `no such module 'XCTest'`, your `xcode-select` points
at the Command Line Tools rather than Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### Keeping permissions across rebuilds

By default `build-app.sh` signs ad-hoc, which produces a designated requirement
pinned to the binary's hash. Every rebuild then looks like a different app to
macOS, and both permissions have to be granted again.

Signing with any valid certificate fixes this — including a free **Apple
Development** identity, which Xcode will create from a plain Apple ID at no
cost. The requirement becomes pinned to the bundle identifier and the
certificate instead of the hash, and stays identical across builds.

The script picks up a single available identity automatically. To choose:

```sh
security find-identity -v -p codesigning          # list what you have
PODTAP_SIGNING_IDENTITY="Apple Development: you@example.com (TEAMID)" \
  ./Scripts/build-app.sh
```

> **Check that the certificate is not revoked.** Signing with a revoked
> certificate makes macOS classify the app as malware and delete it — that is
> what revocation is for. `security find-identity` still lists revoked
> certificates as valid, because revocation is only checked online at
> assessment time. `build-app.sh` verifies with `spctl` after signing and falls
> back to ad-hoc rather than shipping something the system will quarantine.

PodTap clears its own stale TCC records before asking for a permission, so the
usual failure — System Settings showing the app ticked while the app is denied,
and no dialog appearing when you ask — resolves itself from the **Grant…**
button. The equivalent by hand:

```sh
tccutil reset Accessibility com.github.ixjosemi.podtap
tccutil reset ListenEvent com.github.ixjosemi.podtap
```

## Scope

Wired **USB-C EarPods only**.

AirPods are deliberately out of scope: they arrive over Bluetooth AVRCP, expose
no HID device of their own, and cannot be seized this way. Support would need a
completely different and far less reliable mechanism.

## License

MIT.
