#!/bin/bash
PLIST="$HOME/Library/LaunchAgents/local.foldersync.plist"
launchctl bootout gui/$(id -u) "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "Автозапуск отключён. Папка ~/.foldersync (настройки, журналы, резервные копии) оставлена."
