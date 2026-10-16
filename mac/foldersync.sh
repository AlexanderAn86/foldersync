#!/bin/bash
# foldersync — two-way sync of selected local folders with Google Drive via rclone bisync.
# Config: ~/.foldersync/pairs.conf   (lines: LOCAL_PATH => REMOTE:PATH ; '#' = comment)
# Usage: foldersync.sh            — sync all pairs
#        foldersync.sh --init     — first run (resync) for pairs that were never synced
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"

BASE="$HOME/.foldersync"
CONF="$BASE/pairs.conf"
STATE="$BASE/state"
LOGDIR="$BASE/logs"
BACKUP_LOCAL="$BASE/backup"
LOCK="$BASE/run.lock"
mkdir -p "$STATE" "$LOGDIR" "$BACKUP_LOCAL"
LOG="$LOGDIR/$(date +%Y-%m).log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
notify() { osascript -e "display notification \"$1\" with title \"foldersync\"" >/dev/null 2>&1 || true; }

command -v rclone >/dev/null 2>&1 || { log "ERROR rclone not found"; notify "rclone не найден"; exit 1; }
[ -f "$CONF" ] || { log "ERROR no config $CONF"; exit 1; }

# do not run twice at the same time
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then rm -rf "$LOCK"; mkdir "$LOCK"; else exit 0; fi
fi
trap 'rm -rf "$LOCK"' EXIT

INIT=0; [ "${1:-}" = "--init" ] && INIT=1
ERRORS=0

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  [[ "$line" == *"=>"* ]] || continue
  LOCAL="$(echo "${line%%=>*}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  REMOTE="$(echo "${line#*=>}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  LOCAL="${LOCAL/#\~/$HOME}"
  [ -n "$LOCAL" ] && [ -n "$REMOTE" ] || continue
  ID="$(printf '%s' "$LOCAL|$REMOTE" | shasum 2>/dev/null | cut -c1-12)"
  RNAME="${REMOTE%%:*}"; RPATH="${REMOTE#*:}"

  [ $INIT -eq 1 ] && [ ! -f "$STATE/$ID.ok" ] && mkdir -p "$LOCAL"
  if [ ! -d "$LOCAL" ]; then log "ERROR [$ID] local folder missing: $LOCAL"; notify "Нет папки: $LOCAL"; ERRORS=$((ERRORS+1)); continue; fi

  ARGS=( bisync "$LOCAL" "$REMOTE"
    --create-empty-src-dirs --resilient --recover --max-lock 2m
    --compare size,modtime --conflict-resolve newer --conflict-loser num --conflict-suffix conflict --suffix-keep-extension
    --backup-dir1 "$BACKUP_LOCAL/$ID" --backup-dir2 "$RNAME:_foldersync_backup/$ID"
    --exclude ".DS_Store" --exclude "Thumbs.db" --exclude "desktop.ini" --exclude "~\$*" --exclude ".~lock.*" --exclude "*.tmp" --exclude ".tmp.drivedownload/**" --exclude ".tmp.driveupload/**"
    --drive-skip-gdocs --log-file "$LOG" --log-level NOTICE )

  if [ ! -f "$STATE/$ID.ok" ]; then
    if [ $INIT -eq 1 ]; then
      log "INIT [$ID] $LOCAL <=> $REMOTE"
      rclone mkdir "$REMOTE" >> "$LOG" 2>&1
      # bisync cannot work with an empty folder on both sides: add a marker file
      if [ -z "$(ls -A "$LOCAL" 2>/dev/null)" ] && [ -z "$(rclone lsf "$REMOTE" 2>/dev/null | head -1)" ]; then
        echo "This folder is synced by foldersync. Do not delete this file while the folder is empty." > "$LOCAL/_foldersync.txt"
      fi
      if rclone "${ARGS[@]}" --resync --resync-mode newer; then touch "$STATE/$ID.ok"; log "INIT OK [$ID]"
      else log "ERROR INIT [$ID]"; notify "Ошибка первой синхронизации: $LOCAL"; ERRORS=$((ERRORS+1)); fi
    else
      log "SKIP [$ID] not initialized, run: foldersync.sh --init"
    fi
    continue
  fi

  if rclone "${ARGS[@]}"; then log "OK [$ID] $LOCAL"
  else log "ERROR [$ID] $LOCAL (see log)"; notify "Ошибка синхронизации: $(basename "$LOCAL")"; ERRORS=$((ERRORS+1)); fi
done < "$CONF"

exit $ERRORS
