# Runbook

## Initial provisioning

```bash
sudo ./scripts/provision.sh install
```

Follow prompts for:
- existing admin username (created during imaging)
- SSH public key
- VPN endpoint
- WireGuard UDP port
- DNS

## Post install

```bash
sudo ./scripts/provision.sh verify
pivpn add
pivpn -qr
```

## Router

Set DHCP reservation for the Pi and forward UDP 51820 (or your chosen port).
