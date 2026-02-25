#!/usr/bin/env bash

STATE_DIR="/var/lib/pivpn-bootstrap"
STATE_FILE="$STATE_DIR/state.json"

state_init() {
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  if [[ ! -f "$STATE_FILE" ]]; then
    cat > "$STATE_FILE" <<JSON
{
  "last_checkpoint": "none",
  "last_step": "none",
  "last_status": "none",
  "last_error": "",
  "admin_user": "",
  "endpoint_mode": "",
  "last_run_log": "",
  "last_backup_dir": "",
  "run_started_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "updated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
JSON
    chmod 600 "$STATE_FILE"
  fi
}

state_mark_run_start() {
  state_set_field "run_started_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  state_set_field "last_status" "running"
  state_set_field "last_error" ""
  state_set_field "updated_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

state_set_field() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  local esc
  esc="$(json_escape "$value")"
  awk -v key="$key" -v val="$esc" '
    BEGIN { done=0 }
    {
      if ($0 ~ "^[[:space:]]*\"" key "\"[[:space:]]*:") {
        indent=""
        if (match($0, /^[[:space:]]*/)) {
          indent=substr($0, RSTART, RLENGTH)
        }
        comma=""
        if ($0 ~ /,[[:space:]]*$/) {
          comma=","
        }
        print indent "\"" key "\": \"" val "\"" comma
        done=1
      } else {
        print
      }
    }
    END {
      if (done == 0) {
        # Not expected in current template; keep file unchanged if missing.
      }
    }
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

state_mark_step() {
  state_set_field "last_step" "$1"
  state_set_field "updated_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

state_mark_checkpoint() {
  local cp="$1"
  state_set_field "last_checkpoint" "$cp"
  state_set_field "last_status" "ok"
  state_set_field "last_error" ""
  state_set_field "updated_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

state_mark_failure() {
  local step="$1"
  local err="$2"
  state_set_field "last_step" "$step"
  state_set_field "last_status" "failed"
  state_set_field "last_error" "$err"
  state_set_field "updated_at" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

state_get_field() {
  local key="$1"
  sed -n "s/^[[:space:]]*\"${key}\"[[:space:]]*:[[:space:]]*\"\(.*\)\".*/\1/p" "$STATE_FILE" | head -n 1
}
