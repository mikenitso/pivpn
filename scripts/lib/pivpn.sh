#!/usr/bin/env bash

install_or_repair_pivpn() {
  local endpoint="$1"
  local port="$2"
  local dns="$3"

  if command -v pivpn >/dev/null 2>&1; then
    info "PiVPN already installed; validating existing setup."
    systemctl is-active wg-quick@wg0 >/dev/null 2>&1 || warn "wg-quick@wg0 not active."
    return 0
  fi

  info "Installing PiVPN (WireGuard)."
  curl -fsSL https://install.pivpn.io -o /tmp/pivpn-install.sh
  chmod 700 /tmp/pivpn-install.sh

  # PiVPN installer is interactive. Preserve operator control while pre-validating inputs.
  if ! is_valid_port "$port"; then
    error "Invalid WireGuard port: $port"
    return 1
  fi
  if ! is_valid_hostname_or_ip "$endpoint"; then
    error "Invalid endpoint: $endpoint"
    return 1
  fi

  info "Launching PiVPN installer now. Select WireGuard and use port ${port} and endpoint ${endpoint}."
  bash /tmp/pivpn-install.sh

  info "PiVPN install completed."
  info "Configured DNS preference: $dns"
}

verify_pivpn() {
  if ! command -v pivpn >/dev/null 2>&1; then
    error "PiVPN is not installed."
    return 1
  fi
  if systemctl is-active wg-quick@wg0 >/dev/null 2>&1; then
    info "WireGuard service is active."
  else
    warn "WireGuard service is not active."
    return 1
  fi
}
