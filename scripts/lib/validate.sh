#!/usr/bin/env bash

is_valid_username() {
  local user="$1"
  [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  ((port >= 1 && port <= 65535))
}

is_valid_ssh_pubkey() {
  local key="$1"
  [[ "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]
}

is_valid_hostname_or_ip() {
  local v="$1"
  [[ "$v" =~ ^[A-Za-z0-9.-]+$ ]]
}
