#!/bin/bash
# Remove the setleds NumLock LaunchAgent (and any leftovers from older installs).
set -e
cd "$(dirname "$0")"

UID_NUM="$(id -u)"

echo "==> Removing the per-user LaunchAgent..."
launchctl bootout "gui/${UID_NUM}/com.setleds.numlockd" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.setleds.numlockd.plist"
rm -rf "$HOME/Library/Application Support/setleds"
rm -rf "$HOME/Library/Application Support/numlockd"
rm -f "$HOME/Library/Logs/setleds.log"
rm -f "$HOME/Library/Logs/numlockd.log"

if [ -f /Library/LaunchDaemons/com.setleds.numlockd.plist ]; then
    echo "==> Removing leftover root LaunchDaemon (asks for your admin password)..."
    sudo -p "Password: " bash -c '
        launchctl bootout system/com.setleds.numlockd 2>/dev/null || true
        rm -f /Library/LaunchDaemons/com.setleds.numlockd.plist
        rm -f /var/log/setleds.log
    '
fi

echo "==> Done. NumLock reverts to the macOS default (no toggle)."
echo "    You may also remove 'NumLock daemon' from System Settings ->"
echo "    Privacy & Security -> Input Monitoring."
echo "    The installed binary (~/Library/Application Support/setleds/setleds)"
echo "    was removed. To keep a manual CLI tool, copy ./setleds somewhere"
echo "    on your PATH and run:  setleds +num / -num / ^num / -d +num"
