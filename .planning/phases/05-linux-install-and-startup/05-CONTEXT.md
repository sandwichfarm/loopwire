# Phase 5 Context: Linux Install and Startup

**Status:** In Progress
**Date:** 2026-07-03
**Requirements:** LINUX-01, LINUX-02, LINUX-03, LINUX-04, QUAL-03

## Goal

Build credible Linux install, startup, and compatibility validation paths without mutating the host or claiming
published artifacts before they exist.

## Current Slice

Set up a VM compatibility matrix so Loopwire can be validated across distro, desktop, session, package manager, and
audio-server combinations.

## Scope

- Add target metadata for representative Linux systems.
- Add a non-mutating VM helper script for list, validate, doctor, plan, cloud-init rendering, and explicit launch.
- Add docs explaining the operator workflow and evidence requirements.
- Add a lightweight CI guard for matrix metadata and shell syntax.

## Out of Scope

- No distro image download.
- No host package installation.
- No automatic VM boot in GitHub-hosted CI.
- No install-from-release-artifact proof yet.
- No user-scoped autostart implementation yet.

## Verification Targets

- `bash scripts/vm-matrix.sh validate`.
- `bash scripts/vm-matrix.sh list`.
- `bash scripts/vm-matrix.sh plan --target arch-hyprland-pipewire`.
- `bash scripts/vm-matrix.sh render-cloud-init --target arch-hyprland-pipewire --output /tmp/loopwire-vm-cloud-init`.
- `pnpm check`, `pnpm verify:scripts`, workflow YAML parse, and `git diff --check`.
