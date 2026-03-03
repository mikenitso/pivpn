# Cloudflare DDNS (systemd, no Docker)

This project includes a native shell-based Cloudflare DDNS updater designed for Raspberry Pi use with systemd.

## What it does

- Resolves current public IPv4 using fallback sources.
- Ensures one Cloudflare `A` record exists for your subdomain.
- Creates/updates only when needed.
- Runs every 5 minutes via systemd timer.

## Files created on host

- Runtime script: `/home/<admin_user>/bin/cloudflare-ddns-update.sh`
- Env config: `/etc/default/cloudflare-ddns` (mode `600`, root-owned)
- systemd unit: `/etc/systemd/system/cloudflare-ddns.service`
- systemd timer: `/etc/systemd/system/cloudflare-ddns.timer`

## Cloudflare token scope

Create an API token scoped to your zone with:

- `Zone:DNS:Edit`
- `Zone:Zone:Read`

Restrict it to the specific zone whenever possible.

## Install

```bash
sudo ./scripts/install-cloudflare-ddns-systemd.sh install
```

Prompts collect:
- admin username (for script path)
- Cloudflare zone (`example.com`)
- subdomain (`vpn`)
- API token

## Dry-run (no systemd install)

Use this on non-systemd hosts (like macOS) or in CI to render files only:

```bash
./scripts/install-cloudflare-ddns-systemd.sh install \
  --dry-run \
  --output-dir /tmp/cfddns-test \
  --admin-user pi \
  --zone example.com \
  --subdomain vpn \
  --skip-cloudflare-check
```

Rendered files:
- `/tmp/cfddns-test/etc/default/cloudflare-ddns`
- `/tmp/cfddns-test/etc/systemd/system/cloudflare-ddns.service`
- `/tmp/cfddns-test/etc/systemd/system/cloudflare-ddns.timer`

Inspect rendered output:

```bash
find /tmp/cfddns-test -maxdepth 5 -type f | sort
sed -n '1,200p' /tmp/cfddns-test/etc/systemd/system/cloudflare-ddns.service
sed -n '1,200p' /tmp/cfddns-test/etc/systemd/system/cloudflare-ddns.timer
sed -n '1,120p' /tmp/cfddns-test/etc/default/cloudflare-ddns
```

Linux-only syntax validation for rendered units:

```bash
systemd-analyze verify \
  /tmp/cfddns-test/etc/systemd/system/cloudflare-ddns.service \
  /tmp/cfddns-test/etc/systemd/system/cloudflare-ddns.timer
```

Example using your current domain/subdomain:

```bash
./scripts/install-cloudflare-ddns-systemd.sh install \
  --dry-run \
  --output-dir /tmp/cfddns-test \
  --admin-user mikenitso \
  --zone nitroapps.cloud \
  --subdomain lanternway \
  --skip-cloudflare-check
```

## Verify and operations

```bash
sudo ./scripts/install-cloudflare-ddns-systemd.sh verify
sudo ./scripts/install-cloudflare-ddns-systemd.sh status

# manual single update run
sudo systemctl start cloudflare-ddns.service

# view logs
journalctl -u cloudflare-ddns.service -n 50 --no-pager
```

## Uninstall

```bash
sudo ./scripts/install-cloudflare-ddns-systemd.sh uninstall
# or remove runtime script too
sudo ./scripts/install-cloudflare-ddns-systemd.sh uninstall --purge-script
```
