#!/usr/bin/env bash

SSHD_CONFIG="/etc/ssh/sshd_config"
IPV6_SYSCTL_FILE="/etc/sysctl.d/99-pivpn-bootstrap.conf"

ensure_admin_user() {
  local user="$1"
  if id "$user" >/dev/null 2>&1; then
    info "User $user already exists."
  else
    adduser --disabled-password --gecos "" "$user"
  fi
  usermod -aG sudo "$user"
  install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh"
}

ensure_authorized_key() {
  local user="$1"
  local key="$2"
  local auth_file="/home/$user/.ssh/authorized_keys"
  touch "$auth_file"
  chmod 600 "$auth_file"
  chown "$user:$user" "$auth_file"
  if grep -qxF "$key" "$auth_file"; then
    info "SSH key already present for $user."
  else
    echo "$key" >> "$auth_file"
    chown "$user:$user" "$auth_file"
  fi
}

set_sshd_option() {
  local key="$1"
  local value="$2"
  local file="$3"
  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -i -E "s|^[#[:space:]]*(${key})[[:space:]]+.*|\\1 ${value}|" "$file"
  else
    echo "${key} ${value}" >> "$file"
  fi
}

harden_ssh() {
  backup_file_once "$SSHD_CONFIG"
  local tmp
  tmp="$(mktemp)"
  cp "$SSHD_CONFIG" "$tmp"

  set_sshd_option "PasswordAuthentication" "no" "$tmp"
  set_sshd_option "PermitRootLogin" "no" "$tmp"
  set_sshd_option "PubkeyAuthentication" "yes" "$tmp"

  if sshd -t -f "$tmp"; then
    cp "$tmp" "$SSHD_CONFIG"
    systemctl restart ssh
  else
    rm -f "$tmp"
    error "sshd config validation failed before apply."
    return 1
  fi

  if ! systemctl is-active ssh >/dev/null 2>&1; then
    error "ssh service failed after hardening; restoring backup."
    cp "$RUN_BACKUP_DIR/$(echo "$SSHD_CONFIG" | sed 's#/#_#g')" "$SSHD_CONFIG"
    systemctl restart ssh || true
    return 1
  fi
  rm -f "$tmp"
}

disable_pi_account() {
  if id pi >/dev/null 2>&1; then
    passwd -l pi || true
    usermod -s /usr/sbin/nologin pi || true
  fi
}

configure_ufw() {
  ensure_pkg ufw
  ufw allow OpenSSH
  ufw allow "$1"/udp
  ufw --force enable
}

configure_fail2ban() {
  ensure_pkg fail2ban
  backup_file_once /etc/fail2ban/jail.local
  cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
JAIL
  systemctl enable --now fail2ban
}

configure_unattended_upgrades() {
  ensure_pkg unattended-upgrades
  dpkg-reconfigure -f noninteractive unattended-upgrades
  systemctl enable --now unattended-upgrades
}

configure_disable_ipv6() {
  backup_file_once "$IPV6_SYSCTL_FILE"
  cat > "$IPV6_SYSCTL_FILE" <<'SYSCTL'
# Managed by pivpn bootstrap
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
SYSCTL
  chmod 644 "$IPV6_SYSCTL_FILE"
  sysctl --system >/dev/null
}

verify_security_posture() {
  local failed=0

  if grep -Eq '^PasswordAuthentication[[:space:]]+no' "$SSHD_CONFIG"; then
    info "SSH password auth disabled."
  else
    warn "SSH password auth may still be enabled."
    failed=1
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    info "UFW is active."
  else
    warn "UFW is not active."
    failed=1
  fi

  if systemctl is-active fail2ban >/dev/null 2>&1; then
    info "fail2ban is active."
  else
    warn "fail2ban is not active."
    failed=1
  fi

  if [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 0)" == "1" ]] && \
     [[ "$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo 0)" == "1" ]]; then
    info "IPv6 is disabled (all/default)."
  else
    warn "IPv6 disable sysctl is not fully applied."
    failed=1
  fi

  if id pi >/dev/null 2>&1; then
    if passwd -S pi 2>/dev/null | grep -q ' L '; then
      info "pi account is locked."
    else
      warn "pi account exists and is not locked."
      failed=1
    fi
  fi

  return "$failed"
}
