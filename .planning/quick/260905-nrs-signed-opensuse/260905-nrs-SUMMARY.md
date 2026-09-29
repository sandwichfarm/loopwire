---
status: complete
issue: 37
depends_on: 46
---

# Signed openSUSE repository development

Issue: https://github.com/sandwichfarm/loopwire/issues/37

## Result and stack

The openSUSE Tumbleweed x86_64 development work is complete. This branch intentionally stacks on #36/PR #46 so the
channel can reuse the reviewed exact-release provenance, RPM signing, SSH/POSIX publication, protected environment,
and KVM foundations while retaining an independent target, namespace, state, workflow, bootstrap, activation record,
documentation, and guest proof. The checked-in channel remains `pending`; the five Human operational tasks still own
production hosting, signing custody, GitHub configuration, first public publication, and activation.

## Development checklist evidence

1. **Provider evaluation:** the maintainer runbook compares OBS and project-owned delivery across output identity,
   signing, promotion/recovery, and rolling compatibility. Project-owned delivery was selected because it consumes the
   exact authenticated GitHub Release RPM and supports the existing independently testable publication protocol. OBS
   would produce a provider build requiring provisioned project/build identities and separate provider proof.
2. **Package path:** the generator accepts only the Tumbleweed x86_64 `loopwire-VERSION-1.x86_64.rpm`, authenticates
   the OpenSSL-signed SHA256SUMS plus release-assets manifest, and binds the exact RPM and x86_64 archive to the stable
   tag and public release commit. The public source RPM is never mutated; only a staged copy is repository-signed.
3. **Signing:** an isolated OpenPGP identity signs the staged RPM and `repodata/repomd.xml`. The manifest and signed
   metadata retain separate source/distributed hashes and the public source revision. Zypper is configured with
   `gpgcheck=1`, `repo_gpgcheck=1`, and `pkg_gpgcheck=1`; wrong, unsigned, and tampered inputs fail closed.
4. **Publication/rollback:** openSUSE uses `/opensuse/tumbleweed/x86_64` publicly and isolated private locks, CAS,
   journals, and snapshots under `channels/opensuse-tumbleweed-x86_64`. Immutable objects are retained indefinitely in
   v1. Signature-first/atomic-metadata promotion, interruption recovery, retry idempotence, and freshly signed rollback
   were tested with real Zypper, actual SSH, and live Nginx cache behavior.
5. **Protected automation:** Publish openSUSE Repository uses a checksum-pinned Tumbleweed toolchain and supports stable
   release publication, weekly refresh, and retained-revision rollback. `OPENSUSE_REPOSITORY_ENABLED=true` plus the
   `packages-production` environment gate writes. The job waits for existing release gates, verifies public release
   inputs, publishes over pinned SSH, verifies served HTTPS bytes, and emits a reviewable activation record.
6. **Bootstrap:** the repeat-safe helper accepts Tumbleweed x86_64 only, downloads the fingerprint-addressed public key
   over HTTPS, verifies one complete primary fingerprint before writes, and atomically installs only its managed key
   and `.repo` file. Dry-run has no network or writes. Removal preserves packages, accepted RPM-database trust, and
   unrelated repositories. Docs cover the interactive key prompt, rotation, vendor protection, priority, and cleanup.
7. **Regression tests:** real Zypper accepts the signed repository and rejects wrong/malformed keys, missing/changed
   signatures, changed metadata, and unsigned/tampered/wrong-key RPMs. Generator and publisher tests cover target,
   NEVRA/version/architecture, release provenance, downgrade/repack rejection, deterministic retention, encrypted
   keys, unsafe paths, locks, CAS, every interruption point, permissions, SSH transport, HTTP caching, and rollback.
8. **Tumbleweed lifecycle/compatibility:** a checksum-pinned clean Tumbleweed `20260829` KVM guest used the actual
   public v0.1.0 openSUSE RPM and authenticated release manifest. It installed and reinstalled the baseline, upgraded
   only to the declared synthetic `+zypperfixture1`, rolled back to the public baseline, removed the package, isolated
   trust database, and repository. Evidence binds source/distributed hashes, release commit, signature, transaction
   origin, active candidate, native installed view, vendor, `/usr` bytes, providers, backend JSON, GUI linkage, and a
   real X11 window at every installed stage. Later snapshot runs consume the same explicit target manifest during run
   and verification; a failure blocks activation until repaired or compatibility is narrowed and the lifecycle reruns.
9. **Docs/UI:** homepage, install guide, support matrix, release guide, user/operator guides, packaging docs, navigation,
   and unreleased notes are updated. Pending preserves the authenticated direct-RPM/automatic installer fallback;
   verified-fixture proof switches only openSUSE to `sudo zypper install loopwire` with separate setup guidance. The
   repository is identified as third-party and never described as default-distribution or publicly active.

## Verification

- Final pre-guest `pnpm check` passed requirements/docs, automation, workflow contracts, runtime/install/package gates,
  types, 295 workspace tests, 22 Rust tests, production builds, static-site checks, and APT/Fedora/openSUSE suites.
- `pnpm verify:opensuse-repository` passed in the pinned Tumbleweed image: 7 generator, 27 publisher, 7 bootstrap,
  6 public HTTPS, 3 workflow preflight, workflow contract, 39 raw proof-verifier, and 5 channel-gate cases. The publisher
  exercised actual SSH and real Zypper failure/recovery around mixed metadata.
- Fedora regression verification passed: 13 generator and 27 publisher cases plus bootstrap, public, workflow, proof,
  and UI gates, including real DNF behavior.
- The clean KVM lifecycle at `08a18e4484627e36233ab068891bc468e9613f84` produced 159 evidence files and passed an
  independent replay. The guest is snapshot `20260829`; its image SHA-256 is
  `e80d2d1f9cfb328c79a5031d6a30f9744ec83824f6ba44c41ce831ff829a5dad`. Public baseline source SHA-256 is
  `f6bc10589e6308fdc405faa104835cd6bcc486c4bc3fba95b5808b94267f1d05`, bound to public release commit
  `dfdecf30d681c553a906ceebb13c859bb1b46ef3`.
- Pending and verified-fixture Chromium suites passed all platform, command, keyboard/copy, no-JavaScript, responsive,
  motion/reduced-motion/visibility, openSUSE guide, and setup-link assertions. Correct selected-tab screenshots passed
  visual verdict at 96/100; the checked-in channel and final build were restored to pending.
- Actionlint, ShellCheck, Python/Node/Ruby/Bash syntax, docs/workflow contracts, and whitespace passed. Comprehensive
  review findings for read-only syntax, snapshot-manifest propagation, and workflow path coverage were fixed and the
  re-review approved the result.

## Boundaries

The issue's five Human operational tasks remain unchecked. No production account, OBS project, host, TLS/DNS,
OpenPGP identity, SSH credential, GitHub environment value, repository publication, or website activation was created
or changed. Fixture keys, CA, SSH server, synthetic upgrade, and isolated RPM trust database are disposable.

Zypper authenticates repository metadata and RPMs but does not enforce Loopwire's custom signed verification deadline;
HTTPS/origin control, weekly refresh, and monitoring remain operational requirements. Power-loss and network
filesystems were not exercised; production requires local POSIX lock/fsync/atomic-rename behavior.
