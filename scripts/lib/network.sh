#!/usr/bin/env bash

prompt_endpoint() {
  local default_mode="public_ip"
  local mode
  mode="$(prompt_default "VPN endpoint mode (public_ip/ddns)" "$default_mode")"
  printf '%s\n' "$mode"
}

print_router_reminder() {
  local port="$1"
  info "Router reminder: forward UDP ${port} to this Pi's DHCP-reserved LAN IP."
}
