# BrightnessKeys

A tiny macOS menu bar app that makes your keyboard's brightness keys adjust **the display your pointer is on**.

- Pointer on an external monitor → the monitor's real backlight changes over DDC/CI, with an on-screen level indicator on that monitor.
- Pointer on your MacBook's screen → the keys behave exactly as macOS normally does (native HUD, auto-brightness untouched).
- Apple displays (Studio Display, Pro Display XDR) are controlled natively.
- **Option + Shift** + brightness key adjusts in quarter steps.
- The menu bar icon shows a brightness slider for every connected display.

## Requirements

- macOS 14 or later on Apple silicon
- An external monitor that supports DDC/CI (most do; some disable it in the monitor's own menu)

## Install

1. Download the latest **BrightnessKeys-x.y.z.zip** from [Releases](https://github.com/rkanjani/BrightnessKeys/releases/latest). It is signed with Developer ID and notarized by Apple.
2. Unzip it, drag **BrightnessKeys.app** to Applications, and open it.
3. Allow **BrightnessKeys** in **System Settings → Privacy & Security → Accessibility**. That permission is what lets the app catch the brightness keys before macOS does.

### Build from source

```bash
git clone https://github.com/rkanjani/BrightnessKeys.git
cd BrightnessKeys
./build.sh --install
open ~/Applications/BrightnessKeys.app
```

Local builds are ad-hoc signed, so macOS treats each rebuild as a new app: toggle the Accessibility permission off and on after rebuilding. `./release.sh <version>` produces a signed, notarized release (see the script for the one-time setup).

## Command line

The binary also works as a quick CLI, handy for testing a monitor:

```bash
~/Applications/BrightnessKeys.app/Contents/MacOS/BrightnessKeys --list
~/Applications/BrightnessKeys.app/Contents/MacOS/BrightnessKeys --set DELL 60
```

## How it works

| File | Role |
| --- | --- |
| `Sources/KeyTap.swift` | A `CGEventTap` that watches for the brightness media keys and swallows them when the pointer is on an external display |
| `Sources/Displays.swift` | Finds displays, pairs each external monitor with its `IOAVService`, and reads/writes VCP code `0x10` (luminance) over DDC/CI; uses DisplayServices for built-in and Apple displays |
| `Sources/HUD.swift` | The brightness overlay |
| `Sources/main.swift` | Menu bar item, sliders, and Launch at Login |

Writes are coalesced so holding a key never builds up a queue of slow DDC transactions. If you change brightness with the monitor's own buttons, the app re-reads the level the next time you press a key.

## Privacy

BrightnessKeys has no network access and collects nothing. The event tap only looks at brightness keys; every other key event passes through untouched.

## License

[MIT](LICENSE)
