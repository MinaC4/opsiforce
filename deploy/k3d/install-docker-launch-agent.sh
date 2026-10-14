#!/bin/sh
set -eu

agent_dir="$HOME/Library/LaunchAgents"
agent_path="$agent_dir/com.opsiforce.start-docker.plist"
launch_domain="gui/$(id -u)"
mkdir -p "$agent_dir"
cat > "$agent_path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.opsiforce.start-docker</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>Docker</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
</dict>
</plist>
PLIST
chmod 600 "$agent_path"
launchctl bootout "$launch_domain" "$agent_path" >/dev/null 2>&1 || true
launchctl bootstrap "$launch_domain" "$agent_path"
launchctl kickstart "$launch_domain/com.opsiforce.start-docker"

echo 'Docker Desktop is configured to start when this user signs in.'
