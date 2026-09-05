---
status: complete
---

# Make installing Loopwire the homepage default

Tracking: https://github.com/sandwichfarm/loopwire/issues/34

## Intent and scope

Replace the source-first homepage install card with an automatic installer and accessible platform tabs, preserving the existing visual design. Affects platform integration and website/docs only; no audio, desktop runtime, dependency, or release changes.

## Plan

1. Extend the canonical signed installer with distro-aware package selection, embedded release public key, explicit progress/error steps, safe repeated installs/upgrades, and portable fallback. Preserve existing flags and signed checksum/archive rejection checks. Keep its public copy synchronized.
2. Add Automatic (default), Arch, Debian/Ubuntu, Fedora, openSUSE, Nix/NixOS, portable Linux, and Source install tabs. Show real published commands, platform/version boundaries, keyboard navigation, selected-command copying, and honest fallback guidance.
3. Update installation docs, README, and unreleased notes. Open actionable GitHub issues for reducible multi-command platform installs, excluding source builds. Do not disguise multiple steps by joining them with shell separators.

## Verification

- Regression fixtures first: signed local installs, repeat installs/upgrades, platform/architecture selection, dry-run, missing tools, checksum/signature/download failure, and unsafe archive rejection. Stub package managers; never install packages on this workstation.
- Run the real published tarball through the installer into a temporary prefix, using the embedded key, and exercise installed commands.
- Build the combined website; browser-test tabs, keyboard focus, clipboard success/failure, no-JS fallback, desktop/mobile layout and overflow. Compare screenshots with the existing design and persist visual verdict.
- Run shell syntax/static checks, installer/release verification, docs checks, lint/typecheck, tests, full build/static-site verification, and the standard pnpm check gate.
- Review resulting diff and record evidence and known host/platform gaps in the quick-task summary and STATE.md.

## Constraints

Use current published assets and existing packages. No new dependencies, package repositories, host audio changes, or deployment. Native distro packages must match published targets. Non-Linux and unsupported architectures fail with an actionable diagnostic. Release signatures remain required by default.
