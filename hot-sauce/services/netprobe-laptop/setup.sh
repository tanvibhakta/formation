#!/bin/zsh
# Runs netprobe.py on this laptop every 60 seconds as a second client for the home-network
# experiments. Idempotent: re-run after editing netprobe.py.
set -euo pipefail
here=${0:A:h}
root="$HOME/network-observability"
plist="$HOME/Library/LaunchAgents/com.tanvi.netprobe-laptop.plist"
mkdir -p "$root/logs" "${plist:h}"
cp "$here/netprobe.py" "$root/netprobe.py"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.tanvi.netprobe-laptop</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/python3</string><string>$root/netprobe.py</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>$root/logs/launchd.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl kickstart -k "gui/$(id -u)/com.tanvi.netprobe-laptop"
print "Installed $plist; data goes to $root/logs/netprobe.sqlite3"
