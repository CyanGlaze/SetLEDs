#!/bin/bash
# setleds - cloud one-shot installer (prebuilt binary)
#
# Downloads your PRE-BUILT setleds binary from the cloud and installs it as a
# per-user LaunchAgent that toggles the numeric keypad with the NumLock key.
# No local compilation is performed.
#
# Mirror / source:
#   GitHub : https://github.com/CyanGlaze/SetLEDs   (may need a VPN / 科学上网)
#   Gitee  : https://gitee.com/LoveGlaze/SetLEDs    (domestic mirror / 国内加速)
#
# The repo this script is published in is set by REPO_HOST below; that makes the
# one-liner automatically pull the binary from the SAME repo it came from.
#
# Usage:
#   bash setleds.sh            # uses ./setleds next to this script if present,
#                             # otherwise downloads from BASE_URL (see below)
#   or pipe directly:
#     curl -fsSL https://gitee.com/LoveGlaze/SetLEDs/raw/main/setleds.sh | bash
#     curl -fsSL https://raw.githubusercontent.com/CyanGlaze/SetLEDs/main/setleds.sh | bash
#
# Note: a piped run has no local file, so it downloads from BASE_URL (default
# Gitee). To prefer GitHub as the download source, edit BASE_URL in this file.
#
# The only manual step for the end user is granting "Input Monitoring" in
# System Settings (a hard macOS requirement for any key listener, same for all).
set -e

# ===== Where to get the prebuilt "setleds" binary =====
# Priority:
#   1. A local copy sitting next to this script (./setleds) - e.g. after a git
#      clone. This is what makes "bash setleds.sh" use the repo's OWN binary, so
#      a GitHub clone uses GitHub's binary and a Gitee clone uses Gitee's.
#   2. Otherwise (piped via curl) download it from BASE_URL below.
# Edit BASE_URL to point at your preferred repo's raw directory if needed.
BASE_URL="https://gitee.com/LoveGlaze/SetLEDs/raw/main"

# Must run as a normal user, not root (LaunchAgent is per-user).
if [ "$(id -u)" -eq 0 ]; then
    echo "!! Do not run this as root. Run it as your normal user account."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "!! 'curl' is required. Install it via:  xcode-select --install"
    exit 1
fi

UID_NUM="$(id -u)"
BIN_DIR="$HOME/Library/Application Support/setleds"
BIN="$BIN_DIR/setleds"
AGENT_PLIST="$HOME/Library/LaunchAgents/com.setleds.numlockd.plist"
LOG="$HOME/Library/Logs/setleds.log"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
LOCAL_BIN="$SCRIPT_DIR/setleds"

if [ -f "$LOCAL_BIN" ]; then
    echo "==> Using local binary: $LOCAL_BIN"
    cp "$LOCAL_BIN" "$WORK/setleds"
else
    echo "==> Downloading prebuilt setleds from: $BASE_URL/setleds"
    curl -fsSL "${BASE_URL}/setleds" -o "$WORK/setleds"
fi
chmod +x "$WORK/setleds"

# Clear the quarantine xattr so macOS lets the unsigned/ad-hoc binary run.
# (For best portability, sign the binary with a Developer ID before uploading.)
xattr -c "$WORK/setleds" 2>/dev/null || true

# Remove the non-working root LaunchDaemon (it can never open HID devices on
# macOS 26; it just restarts forever). Only triggers if an old one exists.
if [ -f /Library/LaunchDaemons/com.setleds.numlockd.plist ]; then
    echo "==> Cleaning up an old root-daemon install (asks for your admin password)..."
    sudo -p "Password: " bash -c '
        launchctl bootout system/com.setleds.numlockd 2>/dev/null || true
        rm -f /Library/LaunchDaemons/com.setleds.numlockd.plist
        rm -f /var/log/setleds.log
    ' || true
fi

echo "==> Installing per-user LaunchAgent..."
mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp "$WORK/setleds" "$BIN"
chmod 755 "$BIN"
xattr -c "$BIN" 2>/dev/null || true

cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.setleds.numlockd</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN}</string>
        <string>-d</string>
        <string>+num</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG}</string>
    <key>StandardErrorPath</key>
    <string>${LOG}</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/${UID_NUM}/com.setleds.numlockd" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$AGENT_PLIST"

echo
echo "====================================================================="
echo " ONE-TIME PERMISSION - grant Input Monitoring:"
echo
echo "   1. System Settings -> Privacy & Security -> Input Monitoring"
echo "   2. Click \"+\", press Cmd-Shift-. to show hidden folders, and add:"
echo "        ${BIN}"
echo "   3. Make sure the switch next to it is ON."
echo "====================================================================="
echo
echo "(Opening the Input Monitoring pane and showing the binary in Finder...)"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" 2>/dev/null || true
open -R "$BIN" 2>/dev/null || true

read -r -p "After adding & enabling it in System Settings, press Enter here to start the agent..."

launchctl kickstart -k "gui/${UID_NUM}/com.setleds.numlockd"
sleep 2

echo "----- log: ${LOG} -----"
tail -n 10 "$LOG" 2>/dev/null || echo "(no log yet)"

if grep -q "Could not open HID devices" "$LOG" 2>/dev/null; then
    echo
    echo "!! Still denied: the Input Monitoring grant did not take effect."
    echo "   Check the switch is ON, then run:  launchctl kickstart -k gui/${UID_NUM}/com.setleds.numlockd"
else
    echo
    echo "Looks good! Press NumLock now to toggle the keypad."
fi
echo
echo "Notes:"
echo "  - Auto-starts on every login; log: ${LOG}"
echo "  - Do NOT also run 'sudo setleds -d' manually while the agent is"
echo "    running - two listeners would cancel each other out."
echo "  - Uninstall: remove the LaunchAgent plist and the 'setleds' entry"
echo "    from Input Monitoring, or keep uninstall.sh from the repo."
