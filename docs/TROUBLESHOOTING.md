# Troubleshooting

## PiVPN installer did not complete

- Re-run `sudo ./scripts/provision.sh repair`
- Check `/var/log/pivpn-bootstrap/*.log`

## SSH became unreachable after changes

- Use local console access on Pi
- Restore SSH config from latest backup in `/var/backups/pivpn-bootstrap/`
- Restart service: `sudo systemctl restart ssh`

## fail2ban appears inactive

```bash
sudo systemctl status fail2ban
sudo fail2ban-client status sshd
```
