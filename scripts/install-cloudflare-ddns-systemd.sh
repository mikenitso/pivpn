#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="cloudflare-ddns"
DEFAULT_ENV_FILE="/etc/default/${SERVICE_NAME}"
DEFAULT_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DEFAULT_TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"
STATE_FILE="/var/lib/pivpn-bootstrap/state.json"

ENV_FILE="$DEFAULT_ENV_FILE"
SERVICE_FILE="$DEFAULT_SERVICE_FILE"
TIMER_FILE="$DEFAULT_TIMER_FILE"

DRY_RUN="false"
OUTPUT_DIR=""
SKIP_CLOUDFLARE_CHECK="false"

INSTALL_ADMIN_USER=""
INSTALL_ZONE=""
INSTALL_SUBDOMAIN=""
INSTALL_TOKEN=""

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "INFO: $*"
}

require_root() {
  [[ "$EUID" -eq 0 ]] || die "Run as root (sudo)."
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

ensure_pkg() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
}

ensure_dependencies() {
  if [[ "$DRY_RUN" == "true" ]]; then
    need_cmd curl
    need_cmd jq
    return 0
  fi

  need_cmd apt-get
  apt-get update
  ensure_pkg curl
  ensure_pkg jq
}

validate_zone() {
  [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]]
}

validate_subdomain() {
  [[ "$1" =~ ^[A-Za-z0-9-]+$ ]]
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
  local def="$2"
  local value
  read -r -p "$prompt [$def]: " value
  if [[ -z "$value" ]]; then
    printf '%s\n' "$def"
  else
    printf '%s\n' "$value"
  fi
}

prompt_secret() {
  local prompt="$1"
  local value
  while true; do
    read -r -s -p "$prompt: " value
    echo
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
    echo "Value is required."
  done
}

configure_paths_for_mode() {
  if [[ "$DRY_RUN" != "true" ]]; then
    ENV_FILE="$DEFAULT_ENV_FILE"
    SERVICE_FILE="$DEFAULT_SERVICE_FILE"
    TIMER_FILE="$DEFAULT_TIMER_FILE"
    return 0
  fi

  if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="/tmp/cloudflare-ddns-dryrun"
  fi

  mkdir -p "$OUTPUT_DIR"
  OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

  ENV_FILE="$OUTPUT_DIR/etc/default/${SERVICE_NAME}"
  SERVICE_FILE="$OUTPUT_DIR/etc/systemd/system/${SERVICE_NAME}.service"
  TIMER_FILE="$OUTPUT_DIR/etc/systemd/system/${SERVICE_NAME}.timer"
}

detect_admin_user() {
  local guessed=""

  if [[ -n "$INSTALL_ADMIN_USER" ]]; then
    guessed="$INSTALL_ADMIN_USER"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    guessed="$SUDO_USER"
  elif [[ -f "$STATE_FILE" ]]; then
    guessed="$(jq -r '.admin_user // empty' "$STATE_FILE" 2>/dev/null || true)"
  fi

  if [[ -z "$guessed" ]]; then
    guessed="$(prompt_nonempty "Admin username for script install path")"
  else
    guessed="$(prompt_default "Admin username for script install path" "$guessed")"
  fi

  if [[ "$DRY_RUN" != "true" ]]; then
    id "$guessed" >/dev/null 2>&1 || die "User '$guessed' does not exist"
  fi

  printf '%s\n' "$guessed"
}

validate_cloudflare_access() {
  local token="$1"
  local zone="$2"
  local response

  response="$(curl -fsS \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones?name=${zone}&status=active&per_page=1")" || return 1

  [[ "$(printf '%s' "$response" | jq -r '.success // false')" == "true" ]] || return 1
  [[ -n "$(printf '%s' "$response" | jq -r '.result[0].id // empty')" ]]
}

install_runtime_script() {
  local admin_user="$1"
  local src
  local dst_dir
  local dst

  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cloudflare-ddns-update.sh"
  [[ -f "$src" ]] || die "Runtime script not found at $src"

  if [[ "$DRY_RUN" == "true" ]]; then
    dst_dir="$OUTPUT_DIR/home/${admin_user}/bin"
  else
    dst_dir="/home/${admin_user}/bin"
  fi

  dst="${dst_dir}/cloudflare-ddns-update.sh"

  install -d -m 755 "$dst_dir"
  install -m 750 "$src" "$dst"

  if [[ "$DRY_RUN" != "true" ]]; then
    chown root:root "$dst"
  fi

  printf '%s\n' "$dst"
}

write_env_file() {
  local token="$1"
  local zone="$2"
  local subdomain="$3"

  install -d -m 755 "$(dirname "$ENV_FILE")"

  cat > "$ENV_FILE" <<ENV
CF_API_TOKEN=${token}
CF_ZONE_NAME=${zone}
CF_SUBDOMAIN=${subdomain}
CF_PROXIED=false
CF_TTL=1
CF_IP_SOURCES="cloudflare_trace ipify ifconfig_co"
ENV

  chmod 600 "$ENV_FILE"
  if [[ "$DRY_RUN" != "true" ]]; then
    chown root:root "$ENV_FILE"
  fi
}

write_systemd_units() {
  local exec_path="$1"

  install -d -m 755 "$(dirname "$SERVICE_FILE")"

  cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=Cloudflare DDNS updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
EnvironmentFile=${ENV_FILE}
ExecStart=${exec_path}
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
UNIT

  cat > "$TIMER_FILE" <<UNIT
[Unit]
Description=Run Cloudflare DDNS updater every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
RandomizedDelaySec=30s
Persistent=true
Unit=${SERVICE_NAME}.service

[Install]
WantedBy=timers.target
UNIT

  chmod 644 "$SERVICE_FILE" "$TIMER_FILE"
}

enable_and_start() {
  if [[ "$DRY_RUN" == "true" ]]; then
    info "Dry run: systemd commands not executed"
    info "Would run: systemctl daemon-reload"
    info "Would run: systemctl enable --now ${SERVICE_NAME}.timer"
    info "Would run: systemctl start ${SERVICE_NAME}.service"
    return 0
  fi

  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.timer"
  systemctl start "${SERVICE_NAME}.service"
}

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --output-dir)
        OUTPUT_DIR="${2:-}"
        [[ -n "$OUTPUT_DIR" ]] || die "--output-dir requires a path"
        shift 2
        ;;
      --admin-user)
        INSTALL_ADMIN_USER="${2:-}"
        [[ -n "$INSTALL_ADMIN_USER" ]] || die "--admin-user requires a value"
        shift 2
        ;;
      --zone)
        INSTALL_ZONE="${2:-}"
        [[ -n "$INSTALL_ZONE" ]] || die "--zone requires a value"
        shift 2
        ;;
      --subdomain)
        INSTALL_SUBDOMAIN="${2:-}"
        [[ -n "$INSTALL_SUBDOMAIN" ]] || die "--subdomain requires a value"
        shift 2
        ;;
      --token)
        INSTALL_TOKEN="${2:-}"
        [[ -n "$INSTALL_TOKEN" ]] || die "--token requires a value"
        shift 2
        ;;
      --skip-cloudflare-check)
        SKIP_CLOUDFLARE_CHECK="true"
        shift
        ;;
      *)
        die "Unknown install argument: $1"
        ;;
    esac
  done
}

cmd_install() {
  parse_install_args "$@"

  if [[ "$DRY_RUN" == "true" && "$SKIP_CLOUDFLARE_CHECK" != "true" ]]; then
    SKIP_CLOUDFLARE_CHECK="true"
    info "Dry run enabled; defaulting to --skip-cloudflare-check"
  fi

  configure_paths_for_mode
  ensure_dependencies

  local admin_user token zone subdomain exec_path
  admin_user="$(detect_admin_user)"

  if [[ -n "$INSTALL_ZONE" ]]; then
    zone="$INSTALL_ZONE"
    validate_zone "$zone" || die "Invalid zone format"
  else
    while true; do
      zone="$(prompt_nonempty "Cloudflare zone apex (example.com)")"
      validate_zone "$zone" && break
      echo "Invalid zone format."
    done
  fi

  if [[ -n "$INSTALL_SUBDOMAIN" ]]; then
    subdomain="$INSTALL_SUBDOMAIN"
    validate_subdomain "$subdomain" || die "Invalid subdomain format"
  else
    while true; do
      subdomain="$(prompt_nonempty "Subdomain to manage (vpn for vpn.example.com)")"
      validate_subdomain "$subdomain" && break
      echo "Invalid subdomain format."
    done
  fi

  if [[ -n "$INSTALL_TOKEN" ]]; then
    token="$INSTALL_TOKEN"
  elif [[ "$DRY_RUN" == "true" && "$SKIP_CLOUDFLARE_CHECK" == "true" ]]; then
    token="DRY_RUN_TOKEN"
  else
    token="$(prompt_secret "Cloudflare API token")"
  fi

  if [[ "$SKIP_CLOUDFLARE_CHECK" != "true" ]]; then
    info "Validating Cloudflare token and zone access..."
    validate_cloudflare_access "$token" "$zone" || die "Cloudflare validation failed. Check token scope and zone."
  else
    info "Skipping Cloudflare token/zone API validation"
  fi

  exec_path="$(install_runtime_script "$admin_user")"
  write_env_file "$token" "$zone" "$subdomain"
  write_systemd_units "$exec_path"
  enable_and_start

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Dry run artifacts written to: $OUTPUT_DIR"
    info "Rendered env file: $ENV_FILE"
    info "Rendered service: $SERVICE_FILE"
    info "Rendered timer: $TIMER_FILE"
  else
    info "Install complete."
    info "Timer: systemctl status ${SERVICE_NAME}.timer"
    info "Service logs: journalctl -u ${SERVICE_NAME}.service -n 50 --no-pager"
  fi
}

cmd_verify() {
  need_cmd systemctl
  need_cmd jq

  [[ -f "$SERVICE_FILE" ]] || die "Missing $SERVICE_FILE"
  [[ -f "$TIMER_FILE" ]] || die "Missing $TIMER_FILE"
  [[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE"

  local perm
  perm="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE")"
  [[ "$perm" == "600" ]] || die "Expected $ENV_FILE permissions 600, got $perm"

  systemctl is-enabled "${SERVICE_NAME}.timer" >/dev/null || die "${SERVICE_NAME}.timer is not enabled"
  systemctl is-active "${SERVICE_NAME}.timer" >/dev/null || die "${SERVICE_NAME}.timer is not active"

  info "Starting one manual run for verification..."
  systemctl start "${SERVICE_NAME}.service"
  systemctl --no-pager --full status "${SERVICE_NAME}.service" | sed -n '1,20p'

  info "Verification complete."
}

cmd_status() {
  systemctl --no-pager --full status "${SERVICE_NAME}.timer" || true
  echo
  systemctl --no-pager --full status "${SERVICE_NAME}.service" || true
  echo
  journalctl -u "${SERVICE_NAME}.service" -n 30 --no-pager || true
}

cmd_uninstall() {
  local purge_script="false"
  local script_path=""
  if [[ "${1:-}" == "--purge-script" ]]; then
    purge_script="true"
  fi

  if [[ -f "$SERVICE_FILE" ]]; then
    script_path="$(sed -n 's/^ExecStart=//p' "$SERVICE_FILE" | head -n 1)"
  fi

  systemctl disable --now "${SERVICE_NAME}.timer" 2>/dev/null || true
  systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
  rm -f "$SERVICE_FILE" "$TIMER_FILE"
  systemctl daemon-reload

  rm -f "$ENV_FILE"

  if [[ "$purge_script" == "true" ]]; then
    if [[ -n "$script_path" ]]; then
      rm -f "$script_path" || true
    fi
  fi

  info "Uninstall complete."
}

usage() {
  cat <<USAGE
Usage:
  sudo ./scripts/install-cloudflare-ddns-systemd.sh install [options]
  sudo ./scripts/install-cloudflare-ddns-systemd.sh verify
  sudo ./scripts/install-cloudflare-ddns-systemd.sh status
  sudo ./scripts/install-cloudflare-ddns-systemd.sh uninstall [--purge-script]

Install options:
  --dry-run                    Render files only; do not call systemctl
  --output-dir <path>          Output root for dry-run rendered files
  --admin-user <user>          Admin user for runtime script path
  --zone <zone>                Cloudflare zone (example.com)
  --subdomain <name>           Subdomain label (vpn)
  --token <token>              Cloudflare API token
  --skip-cloudflare-check      Skip API validation during install
USAGE
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    install)
      cmd_install "$@"
      ;;
    verify)
      require_root
      cmd_verify
      ;;
    status)
      require_root
      cmd_status
      ;;
    uninstall)
      require_root
      cmd_uninstall "$@"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
