#!/usr/bin/env bash

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This command must run as root (sudo)." >&2
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    return 1
  fi
}

ensure_pkg() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
}

run_apt_upgrade() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    printf '%s\n' "${ID:-unknown}:${VERSION_CODENAME:-unknown}"
    return 0
  fi
  printf '%s\n' "unknown:unknown"
}
