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
| 2-finger move | scroll (content follows your fingers) |
| 2-finger pinch out / in | zoom in / out (trackpad-style magnify; `--zoom-keys` uses ⌘+ / ⌘− instead) |
| 2-finger tap | right click |
| 3-finger swipe up / down | Mission Control / App Exposé |
| 3-finger swipe left / right | next / previous Space |
| 4-finger swipe left / right | next / previous tab (⌃Tab / ⌃⇧Tab: Chrome, Safari, Finder, Terminal…) |

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
an app ignores them, run with `--zoom-keys` to zoom in ⌘+ / ⌘− steps instead.

If the axes are wrong, add `--swap-xy`, `--flip-x` and/or `--flip-y`. Display rotation set in System Settings is
handled automatically. `--help` lists all options.

## Install as an app (starts at login)

```bash
scripts/install.sh            # pass flags here, e.g. scripts/install.sh --zoom-keys --flip-y
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
- `Sources/zentouch/`: IOKit HID access, display lookup, CGEvent injection, menu bar

```bash
swift test
```
