#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DOWNLOADS="/storage/emulated/0/Download"
ROMS="/storage/emulated/0/ROMs"
POLL_SECONDS=10
LOG_FILE="${HOME}/.rom_importer.log"
PID_FILE="${HOME}/.rom_importer.pid"
EXT_MAP_TTL_SECONDS=300
EXT_MAP_READY=0
EXT_MAP_BUILT_AT=0

log() {
  local line
  line="$(printf '[%s] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$*")"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$LOG_FILE"
}

is_running() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

ensure_single_instance() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if is_running "$pid"; then
      log "Already running (pid $pid)."
      exit 0
    fi
  fi
  printf '%s' "$$" > "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT INT TERM
}

stop_running() {
  if [ ! -f "$PID_FILE" ]; then
    log "Not running (no pid file)."
    exit 0
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if is_running "$pid"; then
    kill "$pid"
    log "Stopped (pid $pid)."
  else
    log "Not running (stale pid $pid)."
  fi
  rm -f "$PID_FILE"
  exit 0
}

show_status() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if is_running "$pid"; then
      log "Running (pid $pid)."
      exit 0
    fi
    log "Not running (stale pid $pid)."
    exit 1
  fi
  log "Not running."
  exit 1
}

build_ext_map() {
  declare -gA EXT_TO_ROM=()

  if [ ! -d "$ROMS" ]; then
    log "ROMs folder not found: $ROMS"
    return
  fi

  for system_dir in "$ROMS"/*; do
    [ -d "$system_dir" ] || continue
    if [ ! -f "$system_dir/systeminfo.txt" ]; then
      continue
    fi

    exts_line="$(awk '
      BEGIN { found=0 }
      { line=tolower($0) }
      line ~ /supported file extensions:/ {
        if (getline > 0) { print; found=1 }
      }
      END { if (found==0) exit 1 }
    ' "$system_dir/systeminfo.txt" 2>/dev/null || true)"

    [ -n "$exts_line" ] || continue

    for token in $exts_line; do
      ext="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
      case "$ext" in
        .*) ;;
        *) ext=".$ext" ;;
      esac

      if [ -z "${EXT_TO_ROM[$ext]+x}" ]; then
        EXT_TO_ROM["$ext"]="$system_dir"
      fi
    done
  done
}

ensure_ext_map() {
  local now
  now="$(date +%s)"
  if [ "$EXT_MAP_READY" -eq 0 ] || [ $((now - EXT_MAP_BUILT_AT)) -ge "$EXT_MAP_TTL_SECONDS" ]; then
    build_ext_map
    EXT_MAP_READY=1
    EXT_MAP_BUILT_AT="$now"
  fi
}

unique_target_path() {
  local target="$1"
  if [ ! -e "$target" ]; then
    printf '%s' "$target"
    return
  fi
  local dir base ext stamp
  dir="$(dirname "$target")"
  base="$(basename "$target")"
  ext=""
  if [[ "$base" == *.* ]]; then
    ext=".${base##*.}"
    base="${base%.*}"
  fi
  stamp="$(date '+%Y%m%d%H%M%S')"
  printf '%s/%s_dup_%s%s' "$dir" "$base" "$stamp" "$ext"
}

move_if_supported() {
  local file="$1"
  local filename ext target_dir target_path

  filename="$(basename "$file")"
  if [[ "$filename" != *.* ]]; then
    return
  fi

  ext=".${filename##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  target_dir="${EXT_TO_ROM[$ext]-}"
  if [ -z "$target_dir" ]; then
    return
  fi

  target_path="$(unique_target_path "$target_dir/$filename")"
  mkdir -p "$target_dir"
  mv "$file" "$target_path"
  log "Moved $filename -> $target_dir"
}

process_extracted_folder() {
  local folder="$1"
  local start_ts end_ts

  ensure_ext_map
  if [ "${#EXT_TO_ROM[@]}" -eq 0 ]; then
    log "No supported extensions found in ROMs folders."
    return
  fi

  start_ts="$(date +%s)"
  while IFS= read -r -d '' file; do
    move_if_supported "$file"
  done < <(find "$folder" -type f -print0)
  end_ts="$(date +%s)"
  log "Processed extracted files in $((end_ts - start_ts))s"
}

extract_zip() {
  local zip="$1"
  local dest="$2"
  local start_ts end_ts

  start_ts="$(date +%s)"
  if command -v 7z >/dev/null 2>&1; then
    7z x -y "-o$dest" "$zip" >/dev/null
  elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$zip" -C "$dest" >/dev/null
  elif command -v unzip >/dev/null 2>&1; then
    unzip -o "$zip" -d "$dest" >/dev/null
  else
    log "No extractor found. Install one: pkg install unzip (or p7zip)"
    return 1
  fi
  end_ts="$(date +%s)"
  log "Extracted $(basename "$zip") in $((end_ts - start_ts))s"
}

process_zip() {
  local zip="$1"
  local base dest marker

  base="$(basename "$zip")"
  base="${base%.*}"
  dest="$DOWNLOADS/$base"
  marker="$DOWNLOADS/.${base}.extracted.ok"

  if [ -f "$marker" ]; then
    return
  fi

  mkdir -p "$dest"
  log "Extracting $zip -> $dest"
  if ! extract_zip "$zip" "$dest"; then
    return
  fi

  touch "$marker"
  process_extracted_folder "$dest"

  if [ -d "$dest" ]; then
    find "$dest" -depth -type d -empty -delete >/dev/null 2>&1 || true
    if [ ! -d "$dest" ]; then
      log "Removed empty folder $dest"
    fi
  fi
}

scan_downloads_for_zips() {
  if [ ! -d "$DOWNLOADS" ]; then
    log "Downloads folder not found: $DOWNLOADS"
    return
  fi

  while IFS= read -r -d '' zip; do
    process_zip "$zip"
  done < <(find "$DOWNLOADS" -maxdepth 1 -type f -iname '*.zip' -print0)
}

run_inotify() {
  if ! command -v inotifywait >/dev/null 2>&1; then
    return 1
  fi
  log "Watching $DOWNLOADS for new zip files..."
  inotifywait -m -e close_write,create,moved_to --format '%w%f' "$DOWNLOADS" | while read -r path; do
    case "$path" in
      *.zip|*.ZIP) process_zip "$path" ;;
      *) ;;
    esac
  done
}

main() {
  case "${1:-}" in
    stop)
      stop_running
      ;;
    status)
      show_status
      ;;
    restart)
      stop_running
      ;;
    ""|start)
      ;;
    *)
      printf 'Usage: %s [start|stop|status|restart]\n' "$0"
      exit 2
      ;;
  esac

  ensure_single_instance
  log "Starting ROM importer."
  scan_downloads_for_zips
  if ! run_inotify; then
    log "inotifywait not found. Falling back to polling every ${POLL_SECONDS}s."
    while true; do
      scan_downloads_for_zips
      sleep "$POLL_SECONDS"
    done
  fi
}

main "$@"
