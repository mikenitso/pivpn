# pivpn

Interactive, idempotent Raspberry Pi OS Lite provisioning for a secure PiVPN (WireGuard) server.

## Start

- Plan: `PLAN.md`
- Operator docs: `docs/README.md`

## Commands

```bash
sudo ./scripts/provision.sh install
sudo ./scripts/provision.sh verify
sudo ./scripts/provision.sh audit
sudo ./scripts/provision.sh repair
sudo ./scripts/provision.sh rollback --to ssh_hardening_complete
sudo ./scripts/install-cloudflare-ddns-systemd.sh install
./scripts/install-cloudflare-ddns-systemd.sh install --dry-run --output-dir /tmp/cfddns-test --admin-user pi --zone example.com --subdomain vpn --skip-cloudflare-check
```
