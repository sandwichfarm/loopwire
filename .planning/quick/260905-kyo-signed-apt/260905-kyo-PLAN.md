---
status: implementing
issue: 35
---

# Signed APT repository development

Goal: complete the development checklist in #35, verify it, and open one dedicated PR containing `resolves #35`.
The overall goal continues with #36 and then #37 after this PR is opened. Production accounts, keys, credentials,
and the first public activation remain the separately listed human operational work.

## Contract and decisions

- Target Ubuntu 24.04 and Debian 13, amd64, using the existing tested native package payload and recipes.
- Reuse existing Python/Bash/Git/OpenSSH tooling and distro APT/GnuPG utilities; no new application dependencies.
- Project-owned HTTPS publication uses a POSIX server over SSH. This provides a verifiable same-filesystem atomic
  InRelease replacement; Bunny's documented PUT interface does not establish the required publication guarantee.
- Suites are ubuntu-24.04 and debian-13, component main. Preserve immutable pool and by-hash URLs indefinitely in
  the first implementation. InRelease is the per-suite commit point; no cross-suite instantaneous transaction claim.
- Keep the server HTTP document root separate from private publication state and retained snapshots. Serialize
  writes, compare the expected current revision, reject immutable collisions, and recover interrupted promotion.
- OpenPGP repository signatures are independent of the existing OpenSSL release checksum signatures. Verify both.
- Metadata is valid for 30 days; provide protected scheduled refresh of the same package set and explicit rollback
  that produces fresh signed metadata. Rollback requires an explicit package downgrade on already upgraded clients.
- Homepage repository commands activate only through validated channel configuration after human public proof;
  until then retain the functional existing installation options. Implement and test the activated UI in fixtures.

## Tasks and ownership

1. Generator and trust verification (`apt_protocol`): scripts/apt-repository.py and tests; Packages/Release/InRelease,
   exact release-package validation, immutable inventory, prior-version retention, version ordering, fresh rollback,
   tamper/path/key/architecture failure tests using real signing and APT tools.
2. Publication (`apt_publisher`): scripts/publish-package-repository.py and tests; local and SSH transports, locking,
   compare-and-swap, immutable snapshots, atomic per-suite promotion/recovery, dry-run and cache configuration.
3. Lifecycle (`apt_guest_surface`): explicit APT mode in the existing VM runner, guest lifecycle script and independent
   evidence verifier; fresh matching guests install/reinstall/upgrade/rollback/remove through HTTPS APT and perform
   real GUI/provider/linkage checks. Preserve historical native proof; label synthetic package revisions as fixtures.
4. Integration (root): scoped bootstrap, release/refresh/rollback workflows, CI inputs, configuration contract,
   gated homepage/install documentation, regression coverage, review, final validation and PR delivery.

## Required evidence

- Every development checkbox in #35 maps to implemented files and an executed check in the summary.
- Repository signatures and actual APT reject wrong keys, altered metadata/packages and incomplete publication.
- Retry, concurrent publication, downgrade and rollback rules are exercised, including actual SSH transport.
- Clean Ubuntu and Debian KVM guests consume the served HTTPS repository, with version/origin/signature and real
  installed GUI/provider checks recorded for all applicable lifecycle transitions.
- Workflow syntax/contract checks, docs/build checks, focused tests and the full local validation pass.
- PR targets the current default branch, has a reviewable diff and `resolves #35`, and explicitly lists the human
  production setup/activation still required. Do not claim public production installation was verified without it.
