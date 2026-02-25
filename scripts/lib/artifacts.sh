#!/usr/bin/env bash

LOG_DIR="/var/log/pivpn-bootstrap"
BACKUP_ROOT="/var/backups/pivpn-bootstrap"

setup_run_artifacts() {
  local ts
  ts="$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$LOG_DIR" "$BACKUP_ROOT"
  chmod 700 "$BACKUP_ROOT"
  RUN_LOG="$LOG_DIR/${ts}.log"
  SNAPSHOT_FILE="$LOG_DIR/${ts}-snapshot.txt"
  RUN_BACKUP_DIR="$BACKUP_ROOT/${ts}"
  mkdir -p "$RUN_BACKUP_DIR"
  chmod 700 "$RUN_BACKUP_DIR"
  touch "$RUN_LOG"
  chmod 600 "$RUN_LOG"
}

start_logging() {
  exec > >(tee -a "$RUN_LOG") 2>&1
}

backup_file_once() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local base
  base="$(echo "$f" | sed 's#/#_#g')"
  local dst="$RUN_BACKUP_DIR/${base}"
  if [[ ! -f "$dst" ]]; then
    cp -a "$f" "$dst"
  fi
}

write_snapshot() {
  {
    echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "hostname=$(hostname)"
    echo "kernel=$(uname -r)"
    if command -v ufw >/dev/null 2>&1; then
      echo "ufw_status=$(ufw status | head -n 1 | tr -s ' ')"
    fi
    if command -v fail2ban-client >/dev/null 2>&1; then
      echo "fail2ban_sshd=$(fail2ban-client status sshd 2>/dev/null | tr '\n' ' ' || true)"
    fi
    if systemctl is-enabled ssh >/dev/null 2>&1; then
      echo "ssh_enabled=true"
    fi
    if command -v pivpn >/dev/null 2>&1; then
      echo "pivpn_installed=true"
    else
      echo "pivpn_installed=false"
    fi
  } > "$SNAPSHOT_FILE"
  chmod 600 "$SNAPSHOT_FILE"
}
