# TouchBarFeedback

[한국어](README.md) | **English**

<p align="center"><img src="docs/demo-en.gif" width="720" alt="Tapping the Touch Bar triggers haptic feedback on the trackpad"></p>

A tiny macOS menu bar app that gives you **haptic feedback on the trackpad** and/or a **click sound** whenever you touch the MacBook Touch Bar.

The Touch Bar has no haptic motor, so taps feel flat. This app detects Touch Bar touches and fires the Force Touch trackpad's haptic engine right below it — with your hands on the keyboard, you feel a subtle "tap" under your palm.

## Features

- Feedback on every Touch Bar touch — Esc, volume slider, app buttons, anything
- Three haptic strengths: Light / Medium / Strong
- Optional click sound (system "Tink")
- Launch at login
- Settings saved automatically; lives in the menu bar, no windows

## Requirements

- MacBook Pro with a Touch Bar
- macOS 13 Ventura or later (tested on macOS 15.5, Apple Silicon)
- Xcode or Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/suinegyzal/TouchBarFeedback.git
cd TouchBarFeedback
./build.sh
open ~/Applications/TouchBarFeedback.app
```

`build.sh` compiles the source and installs `~/Applications/TouchBarFeedback.app`.

### First launch

1. Grant **Input Monitoring** permission:
   System Settings → Privacy & Security → Input Monitoring → turn on TouchBarFeedback
   (the "⚠️ Input Monitoring permission needed" menu item opens that pane for you)
2. The app picks up the permission within a few seconds. Tap the Touch Bar.

> Rebuilding changes the ad-hoc code signature, so you may need to grant the permission again.

## Usage

Click the 👆 icon in the menu bar. The menu follows your system language (Korean or English).

<p align="center"><img src="docs/menu-en.png" width="720" alt="Menu bar settings menu"></p>

| Menu item | What it does |
|---|---|
| Enabled | Turn all feedback on/off |
| Haptic / strength | Trackpad haptic and its strength (choosing one previews it) |
| Click sound | Play a click sound on each tap |
| Launch at login | Start automatically after reboot |

## How it works

1. **Touch detection**: a listen-only `CGEventTap` receives gesture events and keeps only touches where `NSTouch.type == .direct`. Touch Bar touches are direct; trackpad touches are indirect. Events from other apps are never blocked or modified.
2. **Haptics**: to vibrate even when no finger is on the trackpad, it drives the trackpad actuator directly via the private `MultitouchSupport` framework (`MTActuator*` functions).
3. **Sound**: a preloaded system sound is played for minimal latency.

## Known limitations

- Haptics rely on a **private Apple API**, so they may break after a macOS update. This also means the app can't ship on the App Store.
- You feel the vibration on the trackpad, not on the Touch Bar itself.

## Uninstall

Turn off "Launch at login", quit from the menu, then delete the app:

```bash
rm -rf ~/Applications/TouchBarFeedback.app
```

## Credits

Inspired by [HapticKey](https://github.com/niw/HapticKey), an open-source project that pioneered the same idea.

## License

MIT
