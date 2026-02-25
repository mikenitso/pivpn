# Recovery

## When a run fails

1. Read the run log path shown by the script.
2. Correct root cause (network, package mirror, invalid input, etc).
3. Re-run:

```bash
sudo ./scripts/provision.sh repair
```

## Roll back high-risk config

```bash
sudo ./scripts/provision.sh rollback --to ssh_hardening_complete
```

Rollback restores known backup files from `/var/backups/pivpn-bootstrap/<timestamp>/`.
