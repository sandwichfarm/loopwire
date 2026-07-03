# Phase 5 Result: User-Scoped Startup Helper

**Completed:** 2026-07-03
**Requirements:** LINUX-02 support path, LINUX-03 support path, LINUX-04 support path

## Delivered

- Added `scripts/manage-autostart.sh` with:
  - `render`,
  - `install`,
  - `enable`,
  - `disable`,
  - `uninstall`,
  - `status`.
- Added `desktop` mode for XDG autostart at `~/.config/autostart/loopwire.desktop`.
- Added `systemd` mode for a user unit at `~/.config/systemd/user/loopwire.service`.
- Added dry-run support for mutating commands.
- Added `scripts/verify-autostart.sh` for deterministic temp-dir verification.
- Added package scripts:
  - `pnpm autostart:status`,
  - `pnpm autostart:install`,
  - `pnpm verify:autostart`.
- Updated docs so the current GUI autostart path is not confused with future background audio restore.

## Boundaries

- No system directories are modified.
- No startup entry is installed unless the user explicitly runs an install/enable command.
- No claim is made that audio routing restores on boot yet.
- The release installer is not wired to autostart yet because published artifacts do not exist.

## Next Phase 5 Work

- Implement background restore mode in the app/package.
- Wire explicit autostart opt-in into release install flow.
- Add AUR/Nix package smoke checks.
- Run VM target evidence with QEMU/KVM once tooling is available.
