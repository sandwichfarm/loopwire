---
status: complete
issue: 36
depends_on: 45
---

# Signed Fedora repository development

Issue: https://github.com/sandwichfarm/loopwire/issues/36

## Result and stack

The Fedora 44 x86_64 development work is complete. This branch intentionally stacks on #35/PR #45 to reuse its
reviewed SSH/POSIX publication, protected environment, activation gate, and KVM harness. The dedicated Fedora channel
record remains `pending`; the separate Human operational tasks still own production hosting, signing identity,
GitHub configuration, first public publication, and website activation. Until then the existing signed direct RPM and
automatic installer remain visible.

## Development checklist evidence

1. **Provider evaluation:** the maintainer runbook compares COPR and project-owned delivery across output provenance,
   signing, Fedora targeting, promotion, proof, retention, and rollback. Project-owned was selected because it consumes
   the exact project-authenticated release RPM, signs only a staged copy, controls publication and produces local/CI
   proof. COPR output would be a separate provider build needing provider-specific evidence.
2. **Package path:** the generator accepts only Fedora 44 x86_64 `loopwire-VERSION-1.fc44.x86_64.rpm`, while allowing
   the known signed openSUSE sibling in the real GitHub Release. It verifies the OpenSSL release signature, signed
   checksum, RPM digest, NEVRA and public release manifest before repository processing. Source release and distributed
   hashes are recorded separately; the source GitHub RPM is never mutated.
3. **Signing:** `rpmsign` applies an RSA/SHA-256 OpenPGP package signature to the staged repository copy.
   `repodata/repomd.xml.asc` separately authenticates SHA-256 metadata objects. Both are verified using isolated RPM
   and GnuPG databases pinned to the expected primary fingerprint. Passphrases travel only through protected files.
4. **Publication/rollback:** the Fedora publisher retains RPMs, fingerprint keys, checksum-named repodata, and private
   snapshots indefinitely in v1. It validates before writes, locks the origin, requires revision CAS, rejects
   immutable collisions, writes the new signature then atomically commits `repomd.xml`, journals every checkpoint,
   and recovers interrupted or explicitly reviewed expired transactions. Real DNF fails closed during the brief mixed
   signature/XML state and succeeds after recovery. Rollback freshly signs the retained package set.
5. **Protected automation:** Publish Fedora Repository uses a checksum-pinned Fedora 44 container and supports a
   release call, manual publish/refresh/rollback, and weekly refresh. `FEDORA_REPOSITORY_ENABLED=true` plus the
   `packages-production` environment gates all writes. Stable publication waits for the existing GitHub Release and
   evidence gates, re-downloads public assets, publishes over pinned SSH, and verifies every HTTPS-served byte before
   producing a reviewable activation record.
6. **Bootstrap:** the repeat-safe helper targets Fedora 44 x86_64, verifies the HTTPS key's full fingerprint, writes
   only the managed `.repo` and fingerprint key file, and requires `gpgcheck=1`, `repo_gpgcheck=1`, `sslverify=1`,
   `skip_if_unavailable=False`. Dry-run has no network/writes; removal preserves other repositories, installed packages
   and RPM-database trust. Docs explain inspecting/removing previously accepted RPM keys during rotation or compromise.
7. **Regression tests:** real DNF accepts only valid package and repodata signatures and rejects wrong signers,
   unsigned/tampered RPMs and changed metadata. Tests cover name/version/release/architecture, real release sibling
   assets, version order, retention, fresh rollback, deterministic fixed-date candidates, encrypted keys, unsafe paths,
   concurrent locks, CAS, every interruption checkpoint, permissions, actual SSH without remote GPG, Nginx cache/404
   headers and real DNF recovery from a mismatched signature/XML transition.
8. **Clean Fedora lifecycle:** a checksum-pinned Fedora 44 KVM guest consumes the actual public v0.1.0 Fedora RPM,
   authenticated through the project release key, SHA256SUMS, release-assets manifest, public release commit and tar
   RELEASE metadata. The repository-signed baseline is installed/reinstalled through DNF, upgraded to the explicitly
   synthetic `+dnffixture1`, downgraded to the public baseline, removed, and its repository removed. Proof binds DNF
   origin, embedded signatures, source/distributed hashes, installed `/usr` bytes, providers, backend JSON, GUI linkage
   and a real X11 window. Fixture keys use an isolated RPM database that is removed on every exit.
9. **Docs/UI:** Fedora homepage, install guide, support matrix, release guide, user guide, operator runbook, packaging
   docs, navigation and release notes are updated. Pending preserves the existing authenticated local-RPM path;
   verified-fixture browser proof switches only Fedora to `sudo dnf install loopwire` and its separate setup link.
   DNF's custom-deadline replay limitation is explicit. Production activation remains human-owned and the repository
   is never described as a default Fedora repository.

## Verification

- Final `pnpm check` passed: project verification, types, 295 workspace tests, 22 Rust tests, native/package gates,
  production builds, static-site verification, and both APT/Fedora repository suites.
- `pnpm verify:rpm-repository` passed in the pinned Fedora 44 image: 13 generator, 20 publisher, 7 bootstrap,
  6 public HTTPS, 3 workflow preflight, 34 raw proof-verifier and 4 channel-gate cases.
- The publisher suite exercised actual SSH and DNF5. DNF rejected the intentionally interrupted signature/XML pair;
  recovery restored a valid repository. Nginx syntax and live cache/404 headers passed.
- The Fedora 44 KVM lifecycle produced 122 evidence files at `e73c5bb` and passed the independent verifier. Baseline
  source SHA-256 is `5a163db0acd1d2f8c73f8cff1b4cc05f12a3d811bfedaf681ea46f460d4d1fb3`, matching the public release manifest.
- Pending and activated-fixture Chromium runs passed the nine platform panels, commands, keyboard/copy failure and
  recovery, no-JavaScript fallback, responsive widths, signal motion/reduced-motion/visibility checks, and Fedora
  setup link/guide command. The checked-in channel was restored to pending.
- Workflow contracts, actionlint, ShellCheck, Python/Node/Ruby/Bash syntax, docs/build checks and whitespace passed.
  A comprehensive review's public-release provenance finding was fixed and approved on targeted re-review.

## Boundaries

The issue's five Human operational tasks remain unchecked. No production host, TLS/DNS, account, OpenPGP identity,
SSH credential, GitHub environment value, repository publication, or website activation was created or changed.
The project verifier enforces the custom signed metadata deadline; DNF itself verifies signatures but does not enforce
that project-specific expiry tag, so HTTPS/origin control and monitoring remain part of operations.

Power-loss and network filesystems were not exercised; production requires local POSIX flock/fsync/atomic-rename
semantics. The KVM repository signer, TLS CA and upgrade version are disposable fixture material. Only the baseline
source RPM is the actual published v0.1.0 Fedora artifact.
