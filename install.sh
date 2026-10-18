#!/bin/bash
# Install the ALREADY-COMPILED ./setleds as a per-user LaunchAgent.
#
# Build first:   make
# Then install:  ./install.sh
#
# Why not a root LaunchDaemon: on macOS 26 a system-domain daemon has no GUI
# login session and IOHIDManagerOpen is refused with 0xe00002e2 even as root.
# A per-user LaunchAgent runs inside your GUI session and works after a
# one-time "Input Monitoring" grant in System Settings.
set -e
cd "$(dirname "$0")"

UID_NUM="$(id -u)"
BIN_DIR="$HOME/Library/Application Support/setleds"
BIN="$BIN_DIR/setleds"
AGENT_PLIST="$HOME/Library/LaunchAgents/com.setleds.numlockd.plist"
LOG="$HOME/Library/Logs/setleds.log"

if [ ! -x ./setleds ]; then
    echo "!! ./setleds not found - compile it first:  make"
    exit 1
fi

# Remove the non-working root LaunchDaemon (it can never open HID devices,
# it just restarts forever and fills /var/log/setleds.log).
if [ -f /Library/LaunchDaemons/com.setleds.numlockd.plist ]; then
    echo "==> Cleaning up the old root-daemon install (asks for your admin password)..."
    sudo -p "Password: " bash -c '
        launchctl bootout system/com.setleds.numlockd 2>/dev/null || true
        rm -f /Library/LaunchDaemons/com.setleds.numlockd.plist
        rm -f /var/log/setleds.log
    ' || true
fi

echo "==> Installing per-user LaunchAgent..."
mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp setleds "$BIN"
chmod 755 "$BIN"

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

read -r -p "After adding & enabling it in System Settings, press Enter here to restart the agent..."

launchctl kickstart -k "gui/${UID_NUM}/com.setleds.numlockd"
sleep 2

echo "----- log: ${LOG} -----"
tail -n 10 "$LOG" 2>/dev/null || echo "(no log yet)"

if grep -q "Could not open HID devices" "$LOG" 2>/dev/null; then
    echo
    echo "!! Still denied: the Input Monitoring grant did not take effect."
    echo "   Check the switch is ON, then run ./install.sh again"
    echo "   (or: launchctl kickstart -k gui/${UID_NUM}/com.setleds.numlockd)."
else
    echo
    echo "Looks good! Press NumLock now to toggle the keypad."
fi
echo
echo "Notes:"
echo "  - Auto-starts on every login; log: ${LOG}"
echo "  - Do NOT also run 'sudo setleds -d' manually while the agent is"
echo "    running - two listeners would cancel each other out."
echo "  - If you rebuild and reinstall the binary later, re-check the"
echo "    Input Monitoring switch afterwards."
echo "  - Uninstall: ./uninstall.sh"
