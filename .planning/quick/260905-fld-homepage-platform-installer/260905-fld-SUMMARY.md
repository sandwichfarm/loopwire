---
status: complete
---

# Make verified installation the first homepage action

Tracking: [#34](https://github.com/sandwichfarm/loopwire/issues/34)

Implementation commit: `c415386` on `feature/34-homepage-platform-installer`.

## Result

The homepage defaults to `curl -fsSL https://loopwire.app/install.sh | bash`. Nine accessible tabs cover Automatic,
Arch, Ubuntu, Debian, Fedora, openSUSE, Nix/NixOS, portable Linux, and source checkout. Copying follows the selected
panel; keyboard navigation, focus order, mobile layout, clipboard errors, and no-JavaScript fallback are covered.
The obsolete pre-release/deployment notice is removed from the homepage and README.

The canonical installer now selects supported native packages, an existing Arch helper, Nix, or a portable archive.
It embeds the existing release verification key, reports steps and exact commands, verifies signatures/checksums
before native/portable installation, and preserves earlier portable installations during upgrades. Portable
replacement stages files and rolls back failures; failed recovery retains backups and reports their paths. Explicit
method changes stop when an existing portable launcher could shadow the new package. Nix version/reference changes
that cannot be safely performed are rejected before profile mutation.

Manual native commands retain seven explicit verification/install steps. Repository follow-ups document what can
reduce them: [APT #35](https://github.com/sandwichfarm/loopwire/issues/35),
[Fedora #36](https://github.com/sandwichfarm/loopwire/issues/36), and
[openSUSE #37](https://github.com/sandwichfarm/loopwire/issues/37). Source build instructions remain available and do
not require a simplification issue. One-time repository trust setup is explicitly separate in those follow-ups.

## Changed files and simplifications

- `apps/site/src/pages/index.astro`: shared tab renderer and native command formatter; removed source-first/gated copy.
- `scripts/install.sh`: existing canonical installer expanded with platform selection, embedded key, progress, upgrades and recovery.
- `apps/docs/docs/public/install.sh`: synchronized public copy; the combined build also copies the canonical installer.
- `scripts/test-install-platforms.sh`, `scripts/verify-install.sh`: isolated signed fixtures and failure/recovery/migration regression coverage.
- `scripts/e2e-site-install.mjs`, `package.json`: browser checks using the existing system Playwright convention, with no new dependency.
- `scripts/verify-static-site.mjs`, `scripts/verify-docs.sh`: enforce the current install experience instead of stale release-gating text.
- `README.md`, `apps/docs/docs/guide/install.md`, `apps/docs/docs/developer/e2e.md`,
  `apps/docs/docs/release-notes/unreleased.md`: current commands, supported target limits, upgrade behavior, checks and release notes.
- This quick-task plan/summary and `.planning/STATE.md`: durable intent, evidence and completion record.

No audio/backend/application-state code, package recipes, dependencies, lockfiles, release artifacts or deployment configuration changed.

## Verification

- Initial regression checks failed on the old default homepage command and unsupported installer flags before implementation.
- Signed installer/release fixtures pass, including platform/architecture selection, repeat installs, stale-file removal,
  missing tools, download/signature/checksum failures, duplicate records, archive paths/links, package failures,
  piped stdin, no-terminal behavior, Nix profile selection/conflicts and old portable-install migration.
- Review reproduced failed-rollback data loss and interruption windows. Added regressions now prove that recovery
  backups survive failed restoration and signals immediately after library/command backups restore the prior copy.
- The real published x86_64 archive installed twice outside a source checkout using only the embedded verification
  key; the installed background launcher, DSP provider, JACK provider and detector help commands all exited zero.
- The built `/install.sh` was fetched through a local HTTP server and piped into Bash, installed the latest signed
  release into a temporary prefix, and ran the installed background launcher help successfully.
- The commands rendered in all four native tabs downloaded real published assets and the pinned public key;
  signature and checksum verification passed for each exact package.
- Browser checks pass for all nine tabs, command syntax/docs parity, clipboard contents/errors, arrow/Home/End
  navigation, focus order, no-JavaScript fallback, and 320/390/768/1440px layouts. Final visual verdict: 96/100.
- ShellCheck 0.11.0, Bash syntax, public-installer/key synchronization and whitespace checks pass.
- The actual Nix 2.28.6 expression parsed eight profile fixtures, including existing, unrelated, duplicate, tagged,
  and query-reference entries. Current AUR metadata was inspected and declares both published architectures and
  pinned release hashes; the real host dry-run selected the installed yay helper without changing packages.
- `pnpm check` passed all script, requirement, documentation, workflow, runtime, packaging, compiler/lint/typecheck,
  test and build gates: 295 TypeScript tests, 22 Rust tests, and 11 GitHub-setup transport tests. Final installer
  boundary/formatting updates were additionally checked with installer/release fixtures and ShellCheck; final docs
  and markup formatting passed a fresh web build, static-site verification and browser suite.
- All four native targets passed with the exact final installer SHA-256
  `b6cb8e0a902459a320d702adc6fab5cf9ff251b8118e622d898ed77807bfe58f`.
  Each verified the release signature twice, completed both installs, made no changes on the second run, and ran
  `/usr/bin/loopwire --background --help` and `/usr/bin/loopwire-dsp-provider --help` successfully.

| Disposable target | Installed package version | Repeat install |
| --- | --- | --- |
| Ubuntu 24.04 | `0.1.0-1ubuntu24.04` | No changes |
| Debian 13 | `0.1.0-1debian13` | No changes |
| Fedora 44 | `0.1.0-1.fc44` | No changes |
| openSUSE Tumbleweed | `0.1.0-1` | No changes |

The minimal openSUSE image needed `gawk`. Ubuntu's final two-pass test disabled optional apt recommendations in the
container; a separate full-default installation also succeeded before a test-harness problem prevented its later
assertions. The final rerun used immutable per-target harnesses. All smoke containers were removed.

## Verification limits

Container native checks exercise package installation/reinstall and installed command help, not a graphical desktop
or live audio routing. AUR installation, a full Nix package build/profile mutation, and native ARM64 execution were
not performed; isolated fixtures cover those selection boundaries, and the Nix parser was exercised with real Nix.
No host package, audio, startup-service, GitHub release, AUR publication or website deployment was performed.

## Review

Independent review approved the repaired recovery logic and identified the old-portable-to-Nix shadowing edge case;
that case now has a passing regression and stops before changing the profile. No known unresolved installer defect
remains in the requested scope.
