# PiVPN Provisioning

Interactive, idempotent provisioning for Raspberry Pi OS Lite to deploy a secure PiVPN WireGuard host.

## Quick Start

1. Flash Raspberry Pi OS Lite (Bookworm).
2. Boot and connect via SSH.
3. Run a pinned release bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/mikenitso/pivpn/<tag>/bootstrap/install.sh | bash -s -- --tag <tag>
```

## Local Run

```bash
sudo ./scripts/provision.sh install
sudo ./scripts/provision.sh verify
sudo ./scripts/provision.sh audit
sudo ./scripts/provision.sh repair
sudo ./scripts/provision.sh rollback --to ssh_hardening_complete
```

## Safety Model

- Checkpoint state: `/var/lib/pivpn-bootstrap/state.json`
- Run logs: `/var/log/pivpn-bootstrap/`
- Config backups: `/var/backups/pivpn-bootstrap/`

Re-running `install` or `repair` converges to desired state and avoids destructive reset behavior.
