---
status: implementing
issue: 36
depends_on: 45
---

# Signed Fedora repository development

Goal: complete every development task in #36 and open a dedicated PR containing `resolves #36`. This branch is an
intentional stack on #35/PR #45 because the Fedora channel reuses its reviewed SSH/POSIX publication, protected
environment, public activation, and guest-proof foundations. Production provider ownership, credentials, signing
identity and first public activation remain the separately listed human operational tasks.

## Decisions

- Choose a project-owned repository over COPR. It indexes the exact OpenSSL-authenticated release RPM, controls when
  the RPM is signed and verified, supports reviewed revision/CAS/retention/recovery semantics, and can be tested
  locally and over the same restricted SSH origin. COPR rebuilds from source and owns signing/publication timing, so
  its output would need distinct provider build evidence and would not be the existing release artifact.
- Initial scope is Fedora 44 x86_64 only. #37 adds openSUSE independently after this PR is open.
- The repository-distributed copy of the GitHub Release RPM receives a separate OpenPGP RPM signature before its
  final repository hash and lifecycle evidence are recorded. The source release hash and distributed hash stay
  distinct and traceable.
- Require both `gpgcheck=1` for package signatures and `repo_gpgcheck=1` for the detached OpenPGP signature over
  `repodata/repomd.xml`. No local-RPM signature exception applies to the repository path.
- Retain immutable signed RPMs and content-addressed repodata indefinitely in v1. Publication must serialize writers,
  require an expected revision, reject immutable collisions, recover interruption, and publish metadata only after
  every package/content object exists. The implementation must make clients either verify a complete revision or
  fail safely during the promotion boundary; exact commit semantics are recorded after generator/publisher tests.
- Metadata expires after 30 days and gets protected weekly refresh. Rollback selects a retained package set, signs
  fresh metadata, and documents the explicit DNF downgrade needed on already-upgraded clients.
- The checked-in Fedora channel remains pending. Existing signed direct-download and automatic-installer paths stay
  functional until a human reviews the production public proof record and commits activation data.

## Work lanes

1. `fedora_repo_protocol`: exact release authentication, RPM/repository signing, createrepo metadata, manifest,
   retention/rollback and real DNF/tamper tests in a pinned Fedora toolchain.
2. `fedora_publisher`: local/SSH POSIX publication, commit semantics, CAS/locks/recovery, immutable retention, actual
   SSH and HTTP/cache tests.
3. `fedora_guest`: isolated clean Fedora 44 KVM lifecycle and strict raw evidence verifier, including package
   signatures, installed payload hashes, providers and a real GUI window.
4. `fedora_docs`: provider comparison, pending/verified website gate and complete user/operator documentation.
5. Root integration: scoped setup/public verification, protected release/refresh/rollback workflow, configuration
   contracts, CI gates, browser fixtures, final review, issue checklist and PR delivery.

## Required verification

- Real DNF with repository and package signature checks accepts correct content and rejects wrong/unsigned/tampered
  RPMs and metadata. Version/architecture/target and downgrade rules are independently verified.
- Publication proves writer exclusion, CAS, ordering/commit behavior, idempotence, interruption recovery, permissions,
  immutable retention, rollback, actual SSH transport, and public cache behavior without production credentials.
- A clean checksum-pinned Fedora 44 KVM guest performs repository install, reinstall, fixture upgrade, explicit
  rollback/downgrade, removal and repository removal against the final committed development code. Raw proof binds
  source/distributed hashes, signer, origin, versions, installed bytes, providers and GUI behavior.
- Pending and verified-fixture browser states, workflow/action syntax, documentation, focused tests and full project
  gates pass. Public production remains disabled and no human task is reported complete without its real evidence.
