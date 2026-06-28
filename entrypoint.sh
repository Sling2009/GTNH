#!/bin/bash
set -euo pipefail

# Global state for SIGTERM handler — must not be local
FIFO=/tmp/mc_stdin
STOP_REQUESTED=false

_stop() {
  STOP_REQUESTED=true
  if [ -p "$FIFO" ]; then
    echo "stop" >"$FIFO" || true
  fi
}

_download_and_extract() {
  local url="$1" target_dir="$2" version="$3"
  echo "[INFO] Downloading GTNH ${version} server pack..."
  curl -L "$url" -o /tmp/server.zip ||
    {
      echo "[ERROR] Download failed – aborting."
      rm -f /tmp/server.zip
      return 1
    }
  echo "[INFO] Extracting server pack..."
  mkdir -p "$target_dir"
  unzip -o /tmp/server.zip -d "$target_dir" ||
    {
      echo "[ERROR] Extraction failed – aborting."
      rm -f /tmp/server.zip
      rm -rf "$target_dir"
      return 1
    }
  rm /tmp/server.zip
  echo "[INFO] Done."
}

# merge_properties: keep old values, add new keys from new file, never delete
merge_properties() {
  local old="$1" new="$2"
  cp "$old" "${old}.bak"
  while IFS='=' read -r key rest; do
    if [[ "$key" =~ ^[[:space:]]*# ]]; then continue; fi
    key="${key//[[:space:]]/}"
    if [[ -z "$key" ]]; then continue; fi
    if ! grep -qE "^${key}[[:space:]]*=" "$old"; then
      echo "${key}=${rest}" >>"$old"
      echo "[INFO] Config: added new key '${key}' to $(basename "$old")"
    fi
  done <"$new"
}

# merge_json: deep merge — old values win on conflict, new keys are added
merge_json() {
  local old="$1" new="$2"
  cp "$old" "${old}.bak"
  if jq -s '.[0] * .[1]' "$new" "$old" >"${old}.tmp" 2>/dev/null; then
    mv "${old}.tmp" "$old"
  else
    echo "[WARN] Config: JSON merge failed for $(basename "$old") – keeping old file"
    rm -f "${old}.tmp"
  fi
}

# merge_cfg: handles Forge TYPE:key=value format — same rules as merge_properties
merge_cfg() {
  local old="$1" new="$2"
  cp "$old" "${old}.bak"
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ "$line" != *=* ]]; then continue; fi
    local key="${line%%=*}"
    local rest="${line#*=}"
    local trimmed
    trimmed="${key#"${key%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ -z "$trimmed" ]]; then continue; fi
    if ! grep -qF "${trimmed}=" "$old"; then
      echo "    ${trimmed}=${rest}" >>"$old"
      echo "[INFO] Config: added new key '${trimmed}' to $(basename "$old")"
    fi
  done <"$new"
}

# merge_config: dispatch by file extension; copy new files that don't exist yet
merge_config() {
  local old="$1" new="$2"
  if [[ ! -f "$old" ]]; then
    mkdir -p "$(dirname "$old")"
    cp "$new" "$old"
    return
  fi
  case "$old" in
  *.json) merge_json "$old" "$new" ;;
  *.cfg) merge_cfg "$old" "$new" ;;
  *.properties) merge_properties "$old" "$new" ;;
  esac
}

main() {
  local MEM_MIN="${MEM_MIN:-6G}"
  local MEM_MAX="${MEM_MAX:-6G}"

  if [[ -z "${GREGTECH_VERSION:-}" ]]; then
    echo "[ERROR] GREGTECH_VERSION is not set."
    exit 1
  fi
  if [[ -z "${GREGTECH_JAVA_VERSION:-}" ]]; then
    echo "[ERROR] GREGTECH_JAVA_VERSION is not set (e.g. '17-25')."
    exit 1
  fi

  local GTNH_PACK_URL="${GTNH_PACK_URL:-https://downloads.gtnewhorizons.com/ServerPacks/GT_New_Horizons_${GREGTECH_VERSION}_Server_Java_${GREGTECH_JAVA_VERSION}.zip}"

  # --- Version detection ---
  local INSTALLED_VERSION=""
  if [[ -f "$HOME_DIR/.gtnh-version" ]]; then
    INSTALLED_VERSION=$(cat "$HOME_DIR/.gtnh-version")
  fi

  if [[ -z "$(ls -A "$HOME_DIR" 2>/dev/null)" ]]; then
    echo "[INFO] $HOME_DIR is empty – performing first install of GTNH ${GREGTECH_VERSION}..."
    _download_and_extract "$GTNH_PACK_URL" "$HOME_DIR" "$GREGTECH_VERSION"
    chmod +x "$HOME_DIR/startserver-java9.sh" 2>/dev/null || true
    echo "$GREGTECH_VERSION" >"$HOME_DIR/.gtnh-version"
    echo "[INFO] Installation complete."

  elif [[ -z "$INSTALLED_VERSION" ]]; then
    echo "[INFO] Existing installation found without version file – recording version ${GREGTECH_VERSION}."
    echo "$GREGTECH_VERSION" >"$HOME_DIR/.gtnh-version"

  elif [[ "$INSTALLED_VERSION" != "$GREGTECH_VERSION" ]]; then
    echo "[INFO] Update detected: ${INSTALLED_VERSION} → ${GREGTECH_VERSION}"
    _download_and_extract "$GTNH_PACK_URL" /tmp/gtnh-update "$GREGTECH_VERSION"

    echo "[INFO] Replacing mod files..."
    rm -rf "$HOME_DIR/mods" "$HOME_DIR/libraries"
    if [[ -d /tmp/gtnh-update/mods ]]; then cp -r /tmp/gtnh-update/mods "$HOME_DIR/"; fi
    if [[ -d /tmp/gtnh-update/libraries ]]; then cp -r /tmp/gtnh-update/libraries "$HOME_DIR/"; fi
    for f in lwjgl3ify-forgePatches.jar java9args.txt startserver-java9.sh; do
      if [[ -f "/tmp/gtnh-update/$f" ]]; then cp "/tmp/gtnh-update/$f" "$HOME_DIR/"; fi
    done
    chmod +x "$HOME_DIR/startserver-java9.sh" 2>/dev/null || true

    echo "[INFO] Merging configs..."
    if [[ -d /tmp/gtnh-update/config ]]; then
      while IFS= read -r -d '' newfile; do
        local relpath="${newfile#/tmp/gtnh-update/}"
        merge_config "$HOME_DIR/$relpath" "$newfile"
      done < <(find /tmp/gtnh-update/config -type f -print0)
    fi
    if [[ -f /tmp/gtnh-update/server.properties ]]; then
      merge_config "$HOME_DIR/server.properties" /tmp/gtnh-update/server.properties
    fi

    rm -rf /tmp/gtnh-update
    echo "$GREGTECH_VERSION" >"$HOME_DIR/.gtnh-version"
    echo "[INFO] Update to ${GREGTECH_VERSION} complete."

  else
    echo "[INFO] GTNH ${GREGTECH_VERSION} is already installed – skipping download."
  fi

  # --- EULA ---
  if [[ "${EULA:-false}" = "true" ]]; then
    echo "eula=true" >"${HOME_DIR}/eula.txt"
  else
    echo "[ERROR] EULA not accepted. Set EULA=true to start the server."
    exit 10
  fi

  # --- Test mode: skip Java start ---
  if [[ "${SKIP_SERVER_START:-false}" = "true" ]]; then
    echo "[INFO] SKIP_SERVER_START=true – exiting without starting server."
    exit 0
  fi

  # --- Graceful Shutdown ---
  trap _stop SIGTERM SIGINT

  # --- Server loop ---
  while true; do
    rm -f "$FIFO"
    mkfifo "$FIFO"

    echo "[INFO] Starting GTNH ${GREGTECH_VERSION} (Xms=${MEM_MIN} Xmx=${MEM_MAX})..."
    java -Xms"${MEM_MIN}" -Xmx"${MEM_MAX}" -Dfml.readTimeout=180 @"${HOME_DIR}"/java9args.txt -jar "${HOME_DIR}"/lwjgl3ify-forgePatches.jar nogui \
      <"$FIFO" &
    local SERVER_PID=$!

    exec 3>"$FIFO"
    wait $SERVER_PID 2>/dev/null || true
    exec 3>&-

    if $STOP_REQUESTED; then
      echo "[INFO] Stop requested – waiting for server to shut down..."
      while kill -0 $SERVER_PID 2>/dev/null; do sleep 1; done
      break
    fi

    echo "[WARN] Server process exited unexpectedly. Restarting in 12 seconds (Ctrl+C to abort)..."
    for i in 12 11 10 9 8 7 6 5 4 3 2 1; do
      if $STOP_REQUESTED; then break; fi
      echo "[WARN] Restarting in ${i}s..."
      sleep 1
    done
    if $STOP_REQUESTED; then break; fi
    echo "[INFO] Restarting now."
  done

  rm -f "$FIFO"
  echo "[INFO] Server stopped."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
