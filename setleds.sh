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
# Usage:
#   bash setleds.sh            # auto: try GitHub, fall back to Gitee
#   bash setleds.sh github     # force GitHub  (needs 科学上网)
#   bash setleds.sh gitee      # force Gitee   (国内加速)
#   MIRROR=gitee bash setleds.sh
#   or pipe directly:
#     curl -fsSL https://raw.githubusercontent.com/CyanGlaze/SetLEDs/main/setleds.sh | bash
#     curl -fsSL https://gitee.com/LoveGlaze/SetLEDs/raw/main/setleds.sh | bash
#
# The only manual step for the end user is granting "Input Monitoring" in
# System Settings (a hard macOS requirement for any key listener, same for all).
set -e

# ===== Pick the mirror that hosts the prebuilt "setleds" binary (same repo) =====
GITHUB_RAW="https://raw.githubusercontent.com/CyanGlaze/SetLEDs/main"
GITEE_RAW="https://gitee.com/LoveGlaze/SetLEDs/raw/main"

MIRROR_CHOICE="${1:-${MIRROR:-auto}}"
case "$MIRROR_CHOICE" in
  github)
    BASE_URL="$GITHUB_RAW"; MIRROR_NAME="GitHub" ;;
  gitee)
    BASE_URL="$GITEE_RAW"; MIRROR_NAME="Gitee" ;;
  auto|*)
    if curl -fsS --max-time 8 "${GITHUB_RAW}/setleds" -o /dev/null 2>/dev/null; then
      BASE_URL="$GITHUB_RAW"; MIRROR_NAME="GitHub"
    else
      BASE_URL="$GITEE_RAW"; MIRROR_NAME="Gitee"
    fi ;;
esac
BINARY_URL="${BASE_URL}/setleds"

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

echo "==> Downloading prebuilt setleds from ${MIRROR_NAME}: $BINARY_URL"
curl -fsSL "$BINARY_URL" -o "$WORK/setleds"
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
