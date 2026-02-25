## Secure, Minimal Raspberry Pi OS + PiVPN (WireGuard) Git-Based Interactive Provisioning Plan

### Summary
Build a GitHub-hosted provisioning repo that supports a secure one-liner bootstrap, then runs a local interactive installer on a fresh Raspberry Pi OS Lite host. The installer will configure a new admin user, lock down SSH, install PiVPN (WireGuard), apply balanced hardening (including fail2ban), enable unattended security updates, and produce auditable logs/config snapshots. The process is designed for repeatable “from scratch” setup with explicit confirmations, safe re-runs, and graceful failure recovery without requiring reimaging.

### Scope and Success Criteria
- Target host: fresh Raspberry Pi OS Lite (minimal install), intended for VPN server role only.
- VPN stack: PiVPN with WireGuard only.
- Network model: router UDP port forward to Pi, with router DHCP reservation for stable LAN IP.
- Security baseline: balanced hardening, SSH keys only, disable default `pi` account after migration.
- Git workflow: one-liner remote bootstrap pinned to a release tag, checksum-verified before execution.
- Success when:
1. New sudo admin user exists and can SSH via key.
2. Password SSH login is disabled.
3. `pi` account is locked/disabled.
4. UFW is active with required allow rules.
5. fail2ban is active with sshd jail enabled.
6. PiVPN WireGuard is installed and operational.
7. Unattended security upgrades are enabled.
8. Run log + sanitized config snapshot are generated.
9. Script can be re-run to converge partially configured hosts to desired state.
10. Failed runs exit with a clear recovery message and preserve enough state to resume or rollback safely.

### Repository Design
- `bootstrap/install.sh`
- `scripts/provision.sh`
- `scripts/lib/ui.sh`
- `scripts/lib/validate.sh`
- `scripts/lib/system.sh`
- `scripts/lib/security.sh`
- `scripts/lib/pivpn.sh`
- `scripts/lib/network.sh`
- `scripts/lib/artifacts.sh`
- `scripts/lib/state.sh`
- `config/defaults.env`
- `docs/README.md`
- `docs/RUNBOOK.md`
- `docs/RECOVERY.md`
- `docs/TROUBLESHOOTING.md`
- `.github/workflows/ci.yml`

### Public Interfaces and Contracts
- Remote entrypoint (pinned tag only):
  - `curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<tag>/bootstrap/install.sh | bash -s -- --tag <tag>`
- `bootstrap/install.sh` contract:
1. Requires explicit `--tag`.
2. Downloads `provision.sh` bundle for that tag.
3. Verifies SHA256 against release checksums.
4. Executes verified local script.
- `scripts/provision.sh` CLI:
1. `./provision.sh install` (interactive, main path)
2. `./provision.sh verify` (post-checks only)
3. `./provision.sh audit` (print current hardening/VPN status)
4. `./provision.sh repair` (re-apply missing/broken steps idempotently)
5. `./provision.sh rollback --to <checkpoint>` (guided rollback to known-safe stage)
- Config contract (`config/defaults.env`):
  - Non-secret defaults only (port default `51820`, timezone prompt fallback, UFW baseline, unattended-upgrades enabled).
- Artifact contract:
  - `/var/log/pivpn-bootstrap/<timestamp>.log`
  - `/var/log/pivpn-bootstrap/<timestamp>-snapshot.txt` (sanitized; no private keys)
  - `/var/lib/pivpn-bootstrap/state.json` (checkpoint + step result state)
  - `/var/backups/pivpn-bootstrap/<timestamp>/` (pre-change backups for rollback)

### Interactive Flow (Decision-Complete)
1. Preflight:
   - Check OS is Debian/Raspberry Pi OS, root/sudo availability, network connectivity.
   - Confirm running on intended minimal host.
   - Load prior state file if present and offer `resume`, `repair`, or `fresh install` behavior.
2. User setup:
   - Prompt for new admin username.
   - Create user only if missing, add to `sudo`, create `.ssh`, set permissions.
   - Prompt to paste at least one SSH public key (repeatable).
   - Validate key format before write and avoid duplicate keys.
   - Record checkpoint `user_setup_complete`.
3. SSH hardening:
   - Backup `/etc/ssh/sshd_config`.
   - Enforce `PasswordAuthentication no`, `PermitRootLogin no`, key auth on (idempotent edit strategy).
   - Restart sshd and verify service healthy.
   - Auto-rollback ssh config backup if restart/health check fails.
   - Record checkpoint `ssh_hardening_complete`.
4. Account lockdown:
   - Migrate any required keys from `pi` if requested and not already present.
   - Lock password and disable `pi` login/account if still enabled.
   - Record checkpoint `account_lockdown_complete`.
5. Base hardening:
   - `apt update && apt full-upgrade -y`.
   - Install and enable UFW with explicit rules: allow SSH, allow WireGuard UDP port.
   - Install and enable fail2ban (`sshd` jail).
   - Install `unattended-upgrades` and enable security auto-updates.
   - Record checkpoint `base_hardening_complete`.
6. PiVPN/WireGuard:
   - Install PiVPN only if not already installed; otherwise validate/fix config drift.
   - Prompt for VPN endpoint mode (public IP vs DDNS), server port (default `51820`), DNS preference.
   - Validate and apply.
   - Record checkpoint `pivpn_complete`.
7. Post-validation:
   - Confirm `wg` interface/service status.
   - Confirm firewall, fail2ban, and ssh policy.
   - Print router reminder for UDP port forward and DHCP reservation validation.
8. Artifacts:
   - Write timestamped run log and sanitized configuration snapshot.
9. Final summary:
   - Show next commands for client profile creation and QR export.
   - If any step failed, print failed step ID, last good checkpoint, exact recovery command, and log path.

### Security Controls
- Pinned-tag install only; reject branch names like `main`.
- Checksum verification required before execution.
- `set -euo pipefail` and strict input validation in all scripts.
- No secret material committed to repo.
- Backup config before mutation.
- Idempotent guards where practical (user existence, package installed, rule exists).
- Atomic write pattern for edited config files: write temp, validate, then replace.
- Trap-based error handler to emit actionable recovery instructions and persist failure context.

### Testing and Validation Plan
1. Static checks:
   - `shellcheck` for all `.sh` files.
   - `shfmt --diff` style check.
2. Unit-like shell tests (Bats or equivalent):
   - Username validation.
   - SSH key validation.
   - Port and endpoint validation.
3. Integration scenarios:
   - Fresh Raspberry Pi OS Lite VM/device run (`install` happy path).
   - Re-run `install` to validate safe/idempotent behavior.
   - Interrupt run mid-way, then use `repair` to complete without regression.
   - Run `rollback --to <checkpoint>` and confirm host remains accessible.
   - `verify` on configured host.
4. Security scenarios:
   - Confirm SSH password login rejected.
   - Confirm `pi` account is locked.
   - Confirm only required ports open.
   - Confirm fail2ban jail is active and banning works.
5. Artifact checks:
   - Logs created with correct permissions.
   - Snapshot contains no private key material.
   - State/checkpoint file is updated correctly per stage and per failure.

### Rollout Plan
1. Create repo skeleton and CI.
2. Implement `bootstrap/install.sh` with tag + checksum enforcement.
3. Implement `provision.sh install` + libraries.
4. Implement state/checkpoint manager and pre-change backup framework.
5. Implement fail2ban provisioning and verification checks.
6. Add `verify`, `audit`, `repair`, and `rollback` subcommands.
7. Validate on a disposable Pi/VM, including failure-injection scenarios.
8. Publish versioned GitHub release with checksums.
9. Use release-tagged one-liner on production Pi.

### Assumptions and Defaults
- OS baseline is Raspberry Pi OS Lite (Bookworm, 64-bit preferred).
- VPN protocol is WireGuard via PiVPN.
- Exposure is via router UDP forwarding.
- LAN stability uses router DHCP reservation, not static host networking.
- SSH policy is keys-only.
- New admin user is created and default `pi` is disabled.
- Maintenance model is unattended security upgrades (no script-driven full update workflow).
- Artifacts are logs + sanitized snapshot only (no bundled key backup).
- fail2ban is enabled by default with SSH jail.
- Provisioning is idempotent by default; re-running converges state instead of resetting it.
- Recovery defaults to `repair`; rollback is available for high-risk config stages.
