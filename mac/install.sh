#!/bin/bash
# Installs foldersync on macOS: copies script, creates config, registers launchd job (every 15 min).
set -e
BASE="$HOME/.foldersync"; mkdir -p "$BASE"
SRC="$(cd "$(dirname "$0")" && pwd)"
cp "$SRC/foldersync.sh" "$BASE/foldersync.sh"; chmod +x "$BASE/foldersync.sh"
[ -f "$BASE/pairs.conf" ] || cp "$SRC/pairs.conf" "$BASE/pairs.conf"
PLIST="$HOME/Library/LaunchAgents/local.foldersync.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.foldersync</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$BASE/foldersync.sh</string></array>
  <key>StartInterval</key><integer>900</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$BASE/logs/launchd.out</string>
  <key>StandardErrorPath</key><string>$BASE/logs/launchd.err</string>
</dict></plist>
PL
mkdir -p "$BASE/logs"
launchctl bootout gui/$(id -u) "$PLIST" 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "Готово. Настройки: $BASE/pairs.conf ; журнал: $BASE/logs/"
echo "Первый запуск: bash $BASE/foldersync.sh --init"
