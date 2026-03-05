#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/ui.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/validate.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/system.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/state.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/artifacts.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/security.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/pivpn.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/network.sh"

# shellcheck disable=SC1091
source "$ROOT_DIR/config/defaults.env"

CURRENT_STEP="none"
MODE=""

usage() {
  cat <<USAGE
Usage:
  ./scripts/provision.sh install
  ./scripts/provision.sh verify
  ./scripts/provision.sh audit
  ./scripts/provision.sh repair
  ./scripts/provision.sh rollback --to <checkpoint>
USAGE
}

on_error() {
  local exit_code="$?"
  local line_no="$1"
  local msg="step=${CURRENT_STEP} line=${line_no} exit=${exit_code}"
  state_mark_failure "$CURRENT_STEP" "$msg"
  error "Provisioning failed at ${msg}"
  error "Recovery: run './scripts/provision.sh repair' after fixing root cause."
  error "Log: ${RUN_LOG:-not-started}"
  exit "$exit_code"
}

run_step() {
  local step="$1"
  local checkpoint="$2"
  CURRENT_STEP="$step"
  state_mark_step "$step"
  info "Running step: $step"
  "$step"
  state_mark_checkpoint "$checkpoint"
  info "Completed step: $step"
}

step_preflight() {
  local os
  os="$(detect_os)"
  info "Detected OS: $os"
  if ! grep -qE 'debian|raspbian|ubuntu' <<<"$os"; then
    warn "Non-Debian-like OS detected. This script targets Raspberry Pi OS."
  fi

  require_cmd apt-get
  require_cmd systemctl
  require_cmd curl

  if [[ -f "$STATE_FILE" ]]; then
    local status checkpoint
    status="$(state_get_field last_status || true)"
    checkpoint="$(state_get_field last_checkpoint || true)"
    if [[ -n "$status" ]]; then
      info "Existing state found: status=$status checkpoint=$checkpoint"
      if [[ "$MODE" == "install" ]] && [[ "$status" == "failed" ]]; then
        if confirm "Previous run failed. Resume with repair behavior now?"; then
          MODE="repair"
        fi
      fi
    fi
  fi
}

step_user_setup() {
  local admin_user ssh_key suggested_user

  suggested_user="$(state_get_field admin_user || true)"
  if [[ -z "$suggested_user" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    suggested_user="$SUDO_USER"
  fi
  if [[ -z "$suggested_user" ]]; then
    suggested_user="pi"
  fi

  while true; do
    admin_user="$(prompt_default "Enter existing admin username (created during imaging)" "$suggested_user")"
    if is_valid_username "$admin_user"; then
      if id "$admin_user" >/dev/null 2>&1; then
        break
      fi
      warn "User '$admin_user' does not exist on this host."
    else
      warn "Invalid username format."
    fi
  done

  ensure_existing_admin_user "$admin_user"

  while true; do
    ssh_key="$(prompt_nonempty "Paste SSH public key for $admin_user")"
    if is_valid_ssh_pubkey "$ssh_key"; then
      break
    fi
    warn "Invalid SSH public key format."
  done

  ensure_authorized_key "$admin_user" "$ssh_key"
  state_set_field "admin_user" "$admin_user"
}

step_ssh_hardening() {
  harden_ssh
}

step_account_lockdown() {
  disable_pi_account
}

step_base_hardening() {
  run_apt_upgrade
  configure_ufw "$WG_PORT"
  configure_fail2ban
  configure_unattended_upgrades
  configure_disable_ipv6
  configure_disable_wifi
}

step_pivpn() {
  local endpoint_mode endpoint dns port

  endpoint_mode="$(prompt_default "Endpoint mode (public_ip/ddns)" "$ENDPOINT_MODE")"
  state_set_field "endpoint_mode" "$endpoint_mode"

  endpoint="$(prompt_nonempty "Enter VPN endpoint (public IP or DDNS host)")"
  if ! is_valid_hostname_or_ip "$endpoint"; then
    error "Invalid endpoint format."
    return 1
  fi

  port="$(prompt_default "WireGuard UDP port" "$WG_PORT")"
  if ! is_valid_port "$port"; then
    error "Invalid port."
    return 1
  fi

  dns="$(prompt_default "Client DNS" "$VPN_DNS")"

  install_or_repair_pivpn "$endpoint" "$port" "$dns"
  print_router_reminder "$port"
}

step_post_validation() {
  verify_security_posture
  verify_pivpn
}

step_artifacts() {
  write_snapshot
  info "Snapshot: $SNAPSHOT_FILE"
}

run_install_like() {
  setup_run_artifacts
  start_logging
  require_root
  state_init
  state_mark_run_start
  state_set_field "last_run_log" "$RUN_LOG"
  state_set_field "last_backup_dir" "$RUN_BACKUP_DIR"

  trap 'on_error $LINENO' ERR

  run_step step_preflight preflight_complete
  run_step step_user_setup user_setup_complete
  run_step step_ssh_hardening ssh_hardening_complete
  run_step step_account_lockdown account_lockdown_complete
  run_step step_base_hardening base_hardening_complete
  run_step step_pivpn pivpn_complete
  run_step step_post_validation validation_complete
  run_step step_artifacts artifacts_complete

  trap - ERR
  info "Provisioning complete."
  info "Run log: $RUN_LOG"
  info "State file: $STATE_FILE"
}

cmd_verify() {
  require_root
  verify_security_posture
  verify_pivpn
  info "verify completed"
}

cmd_audit() {
  require_root
  if [[ -f "$STATE_FILE" ]]; then
    echo "State file: $STATE_FILE"
    cat "$STATE_FILE"
  else
    echo "State file not found: $STATE_FILE"
  fi

  echo
  echo "Service status:"
  systemctl is-active ssh || true
  systemctl is-active fail2ban || true
  systemctl is-active wg-quick@wg0 || true
  echo
  ufw status || true
}

cmd_repair() {
  MODE="repair"
  run_install_like
}

cmd_rollback() {
  require_root
  local checkpoint=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)
        checkpoint="$2"
        shift 2
        ;;
      *)
        error "Unknown rollback argument: $1"
        usage
        return 1
        ;;
    esac
  done

  if [[ -z "$checkpoint" ]]; then
    error "rollback requires --to <checkpoint>"
    return 1
  fi

  local latest_backup
  latest_backup="$(state_get_field last_backup_dir || true)"
  if [[ -z "$latest_backup" || ! -d "$latest_backup" ]]; then
    latest_backup="$(ls -1dt /var/backups/pivpn-bootstrap/* 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$latest_backup" ]]; then
    error "No backups found at /var/backups/pivpn-bootstrap"
    return 1
  fi

  warn "Restoring config backups from $latest_backup toward checkpoint $checkpoint"
  if [[ -f "$latest_backup/_etc_ssh_sshd_config" ]]; then
    cp "$latest_backup/_etc_ssh_sshd_config" /etc/ssh/sshd_config
    systemctl restart ssh || true
  fi
  if [[ -f "$latest_backup/_etc_fail2ban_jail.local" ]]; then
    cp "$latest_backup/_etc_fail2ban_jail.local" /etc/fail2ban/jail.local
    systemctl restart fail2ban || true
  fi
  if [[ -f "$latest_backup/_etc_sysctl.d_99-pivpn-bootstrap.conf" ]]; then
    cp "$latest_backup/_etc_sysctl.d_99-pivpn-bootstrap.conf" /etc/sysctl.d/99-pivpn-bootstrap.conf
    sysctl --system >/dev/null || true
  fi
  if [[ -f "$latest_backup/_boot_firmware_config.txt" ]]; then
    cp "$latest_backup/_boot_firmware_config.txt" /boot/firmware/config.txt || true
  fi
  if [[ -f "$latest_backup/_boot_config.txt" ]]; then
    cp "$latest_backup/_boot_config.txt" /boot/config.txt || true
  fi

  info "Rollback restore actions completed. Re-run verify and repair as needed."
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    install)
      MODE="install"
      run_install_like
      ;;
    verify)
      cmd_verify
      ;;
    audit)
      cmd_audit
      ;;
    repair)
      cmd_repair
      ;;
    rollback)
      shift
      cmd_rollback "$@"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
