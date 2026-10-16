#!/bin/zsh
# Builds ZenTouch.app into ~/Applications and starts it at every login as a LaunchAgent.
# Usage: scripts/install.sh [zentouch flags, e.g. --zoom-keys --flip-y]
#        scripts/install.sh --uninstall
# Set ZENTOUCH_SIGN_IDENTITY to a code-signing certificate name to keep permissions across rebuilds
# (with the default ad-hoc signature, macOS asks for them again after each rebuild).
set -euo pipefail

LABEL=com.zentouch.agent
BUNDLE_ID=com.zentouch.ZenTouch
APP="$HOME/Applications/ZenTouch.app"
BIN="$APP/Contents/MacOS/zentouch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/zentouch.log"
IDENTITY="${ZENTOUCH_SIGN_IDENTITY:--}"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$APP" "$PLIST"
  echo "ZenTouch uninstalled. You can remove it from System Settings → Privacy & Security lists too."
  exit 0
fi

cd "$(dirname "$0")/.."
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$(dirname "$PLIST")" "$(dirname "$LOG")"
cp .build/release/zentouch "$BIN"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>ZenTouch</string>
  <key>CFBundleDisplayName</key><string>ZenTouch</string>
  <key>CFBundleExecutable</key><string>zentouch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- Menu bar only: no Dock icon. -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"

args="<string>$BIN</string>"
for a in "$@"; do args+="<string>$a</string>"; done

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>$args</array>
  <!-- Shows as "ZenTouch" in System Settings → General → Login Items. -->
  <key>AssociatedBundleIdentifiers</key><string>$BUNDLE_ID</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>RunAtLoad</key><true/>
  <!-- Restart after a crash, but stay stopped after "Quit ZenTouch" until the next login. -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$UID" "$PLIST"
echo "ZenTouch installed at $APP and started; it will start at every login. Logs: $LOG"
echo "Allow ZenTouch under Input Monitoring and Accessibility in System Settings → Privacy & Security,"
echo "then choose Quit ZenTouch from its menu bar icon and start it again:"
echo "  launchctl kickstart -k gui/$UID/$LABEL"
