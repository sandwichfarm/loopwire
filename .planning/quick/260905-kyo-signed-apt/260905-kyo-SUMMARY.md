---
status: complete
issue: 35
---

# Signed APT repository development

Issue: https://github.com/sandwichfarm/loopwire/issues/35

## Result

The development work for the Ubuntu 24.04 and Debian 13 amd64 APT channel is complete. The checked-in channel remains
`pending` until the separately listed human operations provision a production HTTPS/SSH origin, create the signing
identity, configure the protected environment, and perform the first public verification. Existing homepage install
commands remain usable; a complete reviewed activation record switches only the Ubuntu and Debian panels to
`sudo apt install loopwire` and exposes the repository-scoped bootstrap command.

## Development checklist evidence

1. **Layout/configuration:** `apt-repository.py` defines separate `ubuntu-24.04` and `debian-13` suites under
   `main/binary-amd64`, suite-specific pool paths, retained SHA-256 by-hash indexes, stable dpkg version ordering,
   30-day signed metadata, indefinite v1 immutable retention, and a strict manifest. The operator runbook specifies
   every variable, secret, path, permission, cache, monitoring, and key-rotation boundary.
2. **Generation:** build verifies the existing OpenSSL-signed release manifest and exact internal deb identity before
   preserving those package bytes. It creates Packages/Packages.gz, Release, OpenPGP clear-signed InRelease, exported
   fingerprint key, by-hash objects, and the independently validated inventory. Verify checks the entire trust chain.
3. **Publication/rollback:** the local/SSH publisher validates before writes, requires pinned host trust, locks the
   POSIX origin, uses revision compare-and-swap, rejects immutable collisions, retains private snapshots, promotes
   immutable objects before metadata, and atomically replaces each suite's InRelease. Durable journals resume every
   interruption point; expired recovery is explicit and demands immediate refresh. Rollback re-signs selected
   package sets with fresh dates. The Nginx example serves only `ROOT/public`, revalidates metadata and long-caches
   immutable URLs.
4. **Protected automation:** Publish APT Repository supports release-triggered publish, operator publish/refresh/
   rollback, and weekly expiry refresh. `APT_REPOSITORY_ENABLED=true` and `packages-production` gate writes. Stable
   release publication waits for the existing GitHub Release/evidence gates, re-downloads and verifies public release
   assets, then verifies every HTTPS-served byte before producing a reviewable activation record. Preflight rejects
   unsafe configuration before key or origin access.
5. **Bootstrap:** the repeat-safe helper supports Ubuntu 24.04 and Debian 13 amd64, downloads only HTTPS key material,
   pins the full fingerprint, uses `/etc/apt/keyrings` and a deb822 source with `Signed-By`, preserves unrelated
   sources, rejects symlink escapes, supports no-network dry-run and safe removal, and never uses `apt-key` or insecure
   APT options. User docs cover install, updates, repair, explicit downgrade, source removal, trust and key changes.
6. **Regression tests:** the dedicated suite runs real GPG/OpenSSL/dpkg/APT checks plus an actual disposable SSH
   server. It rejects unsigned or tampered metadata, modified packages, wrong signers, bad suite/package identity,
   downgrades outside explicit rollback, unsafe files, stale CAS, concurrent access and origin drift. It exercises 22
   publisher cases, all resumable checkpoints, permissions under umask 077, expired-journal recovery, public HTTPS
   tampering, bootstrap containment and a real Zstandard deb on the pinned Debian 13 toolchain.
7. **Matching guests:** clean checksum-pinned Ubuntu 24.04 and Debian 13 KVM guests installed from a guest-only HTTPS
   repository using the real scoped bootstrap. Each performed install, reinstall, a synthetic `+aptfixture1` upgrade,
   explicit downgrade/rollback, removal and source removal. The verifier binds repository origin, versions, signed
   package hashes, every installed `/usr` file, providers/backend detector, GUI linkage and a real X11 application
   window. The synthetic version reuses the authenticated v0.1.0 payload and is lifecycle evidence, not a release.
8. **Docs/UI:** homepage, install guide, support matrix, release guide, user APT guide, maintainer runbook, release
   notes, and navigation are updated. Pending and verified-fixture browser tests prove the fallback and activated
   states. Production activation remains the human step that supplies verified public values; Loopwire is never
   described as part of a distribution's default repository.

## Verification

- `pnpm check` passed after the final review change: all project verification, types, 295 workspace tests, 22 Rust
  tests, builds, static-site validation and the dedicated APT suite.
- `pnpm verify:apt` passed: 13 generator, 22 publisher (including actual SSH), 11 bootstrap, 9 public HTTPS, 5 workflow
  preflight, 17 proof-verifier, and 4 homepage channel cases.
- Generator tests passed with real APT on both Debian 13 and Ubuntu 24.04; wrong-key, unsigned/tampered metadata and
  modified-package downloads were rejected.
- Ubuntu and Debian lifecycle proof directories each contain 96 evidence files from commit `7849a1b`, revalidated
  successfully with the final portable verifier at `639cbbb`.
- Pending production build browser tests passed all existing install/copy/keyboard/responsive/motion/fallback cases.
  The verified fixture passed those same checks and additionally rendered both short APT commands, their separate
  setup links, and the complete URL/fingerprint setup command. The checked-in record was restored to pending.
- Workflow contracts, actionlint, ShellCheck, Python/Node/Ruby/Bash syntax, docs/build checks and whitespace checks
  passed. Final review's Zstandard portability finding was reproduced, fixed with `dpkg-deb --fsys-tarfile`, covered
  by a real compressed package, and approved on re-review.

## Human operations still open

No production host/account, TLS certificate, SSH credential, OpenPGP identity, GitHub environment value, or public
repository was created or changed. No production publication was triggered. The five Human operational tasks in
issue #35 remain unchecked. The first public run must attach the public URL/fingerprint/revision and clean-client
evidence, then its reviewed `apt-channel.json` can activate the website through a separate commit.

Power-loss behavior and network filesystems were not tested; the publication contract explicitly requires local
POSIX filesystem locking/fsync/atomic-rename semantics. Ubuntu/Debian guests used a disposable local CA and repository
key; fixture trust cannot generate a production activation record.
