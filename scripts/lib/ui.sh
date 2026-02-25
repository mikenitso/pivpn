#!/usr/bin/env bash

log() {
  local level="$1"
  shift
  local now
  now="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '%s [%s] %s\n' "$now" "$level" "$*"
}

info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@"; }

confirm() {
  local prompt="$1"
  local answer
  while true; do
    read -r -p "$prompt [y/n]: " answer
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "Please enter y or n." ;;
    esac
  done
}

prompt_nonempty() {
  local prompt="$1"
  local value
  while true; do
    read -r -p "$prompt: " value
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
    echo "Value is required."
  done
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default]: " value
  if [[ -z "$value" ]]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$value"
  fi
}
