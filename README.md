# zentouch

A user-space touchscreen driver for the **ASUS ZenScreen MB16AMT** on macOS: a do-it-yourself replacement for UPDD Touch-Base.

macOS has no touchscreen support. The MB16AMT's panel is an eGalax EXC3200 controller (USB `0EEF:C000`) that macOS
treats as a generic digitizer, which usually drives the cursor on the wrong screen. zentouch takes exclusive
access to the panel, maps touches onto the ZenScreen wherever it sits in your display arrangement, and posts
ordinary mouse, scroll and keyboard events.

No kernel extension, no DriverKit, no SIP changes.

## Gestures

| Touch | Action |
| --- | --- |
| 1-finger tap | click (double and triple tap work) |
| 1-finger move | drag |
| 1-finger hold (0.6 s) | right click |
| 2-finger move | scroll (content follows your fingers); flick and lift to keep gliding with inertia, touch to stop |
| 2-finger pinch out / in | zoom in / out |
| 2-finger tap | right click |
| **5-finger hold (2 s)** | **open the gestures panel** |

### Customizable gestures

These are set in the gestures panel. Hold 5 fingers still for 2 seconds, or choose **Gestures & Settings…** from
the menu bar icon.

| Gesture | Default |
| --- | --- |
| Hold 2, 3 or 4 fingers still | nothing (a hold only takes over once it has an action) |
| 3- or 4-finger tap | nothing |
| 3-finger swipe up / down | Mission Control / App Exposé |
| 3-finger swipe left / right | next / previous Space |
| 4-finger swipe up / down | Mission Control / App Exposé |
| 4-finger swipe left / right | next / previous tab (⌃Tab / ⌃⇧Tab) |

Each one can do one of three things:
- **A built-in action.** Mission Control, App Exposé, Show Desktop, Apps, Spaces, tab actions (new, close, reopen,
  next, previous), Back/Forward, Spotlight, Screenshot, full screen, minimize, hide, lock screen,
  copy/paste/undo/redo, zoom, right or middle click, volume, mute and media keys.
- **A recorded keyboard shortcut.** Click *Record Shortcut*, then press the keys.
- **Open an app.**

The panel's **Settings** tab sets scroll speed, inertia and glide length, the long-press and multi-finger-hold
durations, touch accuracy, the pinch zoom style (smooth trackpad-style, or ⌘+ / ⌘− steps), and the axis flips.

**Touch accuracy:**
- **Offset** shifts every touch by up to 40 points horizontally and vertically, if clicks land consistently beside
  your finger.
- **Touch area** works like a phone. A tap that lands within that many points of a button, link, checkbox or text
  field snaps onto it, found through macOS Accessibility. Taps that already hit something clickable aren't moved.
  In Chrome and Electron apps this turns on accessibility for web content, which can slow down very large pages a
  little. Changes apply
immediately, so you can try them with your fingers. Press **Save** (⌘S) to keep them, or **Discard Changes** to go
back to the last saved settings. Closing the panel with unsaved changes asks which you want. Saved settings live in
`~/Library/Application Support/ZenTouch/settings.json`.

## Run it

The ZenScreen must be connected so USB data reaches the Mac: a single USB-C cable with DisplayPort Alt Mode works.
With mini-HDMI you also need a USB cable.

```bash
swift build -c release
.build/release/zentouch --dump   # print touches without moving the cursor
.build/release/zentouch          # drive the cursor
```

The first run asks for **Input Monitoring** (reading the panel) and **Accessibility** (posting events) for your
terminal app. Grant both in System Settings → Privacy & Security, then run it again.

Pinch zoom posts the same magnify gesture events a MacBook trackpad sends. Those event fields are undocumented, so if
an app ignores them, switch the panel's pinch zoom setting to steps.

If the axes are wrong, fix them in the panel's Settings tab (or with `--swap-xy`, `--flip-x`, `--flip-y`). Display
rotation set in System Settings is handled automatically. `--help` lists all options; `--show-panel` opens the panel
at launch.

## Install as an app (starts at login)

```bash
scripts/install.sh            # settings live in the gestures panel; flags still work too
scripts/install.sh --uninstall
```

This builds `~/Applications/ZenTouch.app`, a menu bar app with no Dock icon, and registers a LaunchAgent so it
starts at every login and restarts if it crashes. It appears as **ZenTouch** in System Settings → General →
Login Items. The menu bar icon shows the status and has Pause Touch, shortcuts to the permission settings, and Quit
(it stays quit until the next login, or `launchctl kickstart -k gui/$UID/com.zentouch.agent`).

After the first install, allow **ZenTouch** under Input Monitoring and Accessibility in System Settings → Privacy &
Security, then quit and restart it. If the ZenScreen isn't plugged in, or another app holds the panel, ZenTouch waits
and picks it up when it becomes available.

With the default ad-hoc signature, macOS asks for the permissions again after each reinstall. To avoid that, sign
with a code-signing certificate: `ZENTOUCH_SIGN_IDENTITY="Your Certificate Name" scripts/install.sh`.
Logs are in `~/Library/Logs/zentouch.log`.

## Layout

- `Sources/ZenTouchCore/EGalaxReportParser.swift`: decodes input report 6, including hybrid frames with more than 5 contacts
- `Sources/ZenTouchCore/DisplayMapper.swift`: panel to screen coordinates, rotation and calibration
- `Sources/ZenTouchCore/GestureEngine.swift`: touch frames to clicks, drags, scrolls and shortcuts
- `Sources/ZenTouchCore/Momentum.swift`: smartphone-style inertia after a flick
- `Sources/ZenTouchCore/TouchArea.swift`, `Sources/zentouch/TouchTargeter.swift`: snapping taps to nearby targets
- `Sources/ZenTouchCore/GestureActions.swift`, `Settings.swift`: configurable gesture slots, actions and saved settings
- `Sources/zentouch/`: IOKit HID access, display lookup, CGEvent injection, actions, menu bar, gestures panel (SwiftUI)

```bash
swift test
```
