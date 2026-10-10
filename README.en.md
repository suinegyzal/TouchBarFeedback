# TouchBarFeedback

[한국어](README.md) | **English**

<p align="center"><img src="docs/demo-en.gif" width="720" alt="Tapping the Touch Bar triggers haptic feedback on the trackpad"></p>

A tiny macOS menu bar app that gives you **haptic feedback on the trackpad** and a soft **"todok" click sound** whenever you press a button on the MacBook Touch Bar.

The Touch Bar has no haptic motor, so taps feel flat. This app detects Touch Bar touches, fires the Force Touch trackpad's haptic engine right below it, and plays a short keyboard-like tap sound.

## Features

- Feedback only when you press a **button** (taps on gaps or empty space stay silent)
- Three haptic strengths: Light / Medium / Strong
- Click sound: **Todok** (default, synthesized) / Tink / any sound file you choose
- Todok rotates through three slight variations so it never sounds mechanical
- Launch at login
- Menu follows your system language (Korean or English)

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

1. Grant **Accessibility** permission. It's needed to detect touches and locate Touch Bar buttons.
   - When the accessibility prompt appears, click **Open System Settings**.
   - System Settings → Privacy & Security → Accessibility → turn on **TouchBarFeedback**
2. **Quit and relaunch the app.** The permission only takes effect after a relaunch.
3. Press a Touch Bar button.

> **If you rebuild**, the ad-hoc signature changes and the old permission no longer applies, even if the switch looks on. Reset it with the command below, launch the app, grant the permission again, and relaunch.
> ```bash
> tccutil reset All local.touchbarfeedback
> ```

## Usage

Click the 👆 icon in the menu bar.

<p align="center"><img src="docs/menu-en.png" width="720" alt="Menu bar settings menu"></p>

| Menu item | What it does |
|---|---|
| Enabled | Turn all feedback on/off |
| Haptic / strength | Trackpad haptic and its strength (choosing one previews it) |
| Click sound | Toggle the sound and pick which one (choosing one previews it) |
| Launch at login | Start automatically after reboot |

## How it works

1. **Touch detection**: a listen-only `CGEventTap` receives gesture events and keeps only touches whose source device is the Touch Bar (`NSTouch.device.deviceType == 3`). Events from other apps are never blocked or modified.
2. **Button hit-testing**: the Accessibility API reads where the frontmost app and the Control Strip placed their Touch Bar items (`AXFunctionRowTopLevelElements`), and feedback fires only when the touch lands on one.
3. **Haptics**: to vibrate even when no finger is on the trackpad, it drives the trackpad actuator directly via the private `MultitouchSupport` framework (`MTActuator*` functions).
4. **Sound**: the todok sound is synthesized by [`tools/make_sounds.py`](tools/make_sounds.py) into `sounds/`, and preloaded for minimal latency.

## Known limitations

- Haptics rely on a **private Apple API**, so they may break after a macOS update. This also means the app can't ship on the App Store.
- You feel the vibration on the trackpad, not on the Touch Bar itself.

## Troubleshooting

- **No feedback?** Reset the permission with the `tccutil reset` command above, grant it again, and relaunch the app. This fixes most cases.
- **Debug log**: run the command below and relaunch the app; permission state and touch positions are written to `~/Library/Logs/TouchBarFeedback.log`.
  ```bash
  defaults write local.touchbarfeedback debug -bool true
  ```
  Turn it off with `defaults delete local.touchbarfeedback debug`

## Uninstall

Turn off "Launch at login", quit from the menu, then delete the app:

```bash
rm -rf ~/Applications/TouchBarFeedback.app
tccutil reset All local.touchbarfeedback
```

## Credits

Inspired by [HapticKey](https://github.com/niw/HapticKey), an open-source project that pioneered the same idea.

## License

MIT
