---
status: implementing
issue: 37
depends_on: 46
---

# Signed openSUSE repository development

Goal: complete every development task in #37 and open a dedicated PR containing `resolves #37`. This branch is an
intentional stack on #36/PR #46 because the openSUSE channel reuses the exact-release provenance, RPM signing,
content-addressed metadata retention, protected publication, and KVM proof foundations introduced there. Production
provider ownership, credentials, signing identity, GitHub environment configuration, and first public activation
remain the separately listed human operational tasks.

## Decisions

- Choose a project-owned repository over OBS. It publishes the exact authenticated project release RPM, preserves the
  release/source/build identity already recorded by Loopwire, and gives the project explicit promotion, retention,
  rollback, and recovery semantics. OBS would rebuild and sign a distinct output, requiring provider project/build
  identities and provider-specific proof that cannot be produced without the human operational setup.
- Initial scope is openSUSE Tumbleweed x86_64 only. Leap and other architectures remain unsupported until they receive
  their own package and clean-guest validation.
- Reuse the shared RPM repository protocol only where libzypp/Zypper behavior proves it compatible. Keep the target,
  client bootstrap, workflow, public activation record, docs, and guest proof openSUSE-specific.
- Require authenticated repository metadata and embedded RPM signatures. The bootstrap path must preserve Zypper
  checks and may not use `--no-gpg-checks` or `--allow-unsigned-rpm`.
- Retain immutable signed RPMs and content-addressed metadata indefinitely in v1. Publication must serialize writers,
  require revision CAS, reject immutable collisions, recover interruption, and expose only complete revisions or a
  verification failure during promotion.
- The checked-in openSUSE channel remains pending. Existing signed direct-download and automatic-installer paths stay
  visible until a maintainer completes and reviews the production public proof record.

## Work lanes

1. Repository protocol: extend exact-release authentication, RPM/repository signing, metadata manifests, rollback, and
   tamper tests for the openSUSE Tumbleweed target, grounded in real Zypper/libzypp behavior.
2. Publication: extend local/SSH publication, atomic promotion, CAS/locks/recovery, immutable retention, and public
   HTTP proof for the openSUSE namespace.
3. Guest proof: run an isolated clean Tumbleweed KVM lifecycle using the actual public v0.1.0 openSUSE RPM, plus a
   strictly synthetic upgrade, and verify raw provenance, installed bytes, providers, backend JSON, and GUI linkage.
4. Product/docs: add the pending/verified homepage gate, tested bootstrap, provider decision, rolling-snapshot policy,
   support matrix, release/operator guidance, navigation, and unreleased notes.
5. Root integration: protected workflow, config contracts, focused and full gates, browser fixtures, final review,
   issue checklist update, and PR delivery.

## Required verification

- Real Zypper accepts correct signed metadata and package content and rejects wrong, unsigned, or tampered content.
  Version, architecture, target, vendor/origin, downgrade, and repository removal behavior are independently verified.
- Publication proves writer exclusion, CAS, ordering, idempotence, interruption recovery, permissions, immutable
  retention, rollback, actual SSH transport, and public cache behavior without production credentials.
- A clean checksum-pinned Tumbleweed KVM guest performs repository install, reinstall, fixture upgrade, explicit
  rollback/downgrade, removal, and repository removal against final committed development code. Evidence records the
  snapshot and binds source/distributed hashes, signer, origin/vendor, versions, installed bytes, providers, and GUI.
- Documentation defines a repeatable later-snapshot compatibility run and requires disabling activation/escalating a
  failed snapshot until the package or compatibility declaration is repaired and the full lifecycle reruns.
- Pending and verified-fixture browser states, workflow/action syntax, docs, focused tests, and full project gates pass.
  Public production remains disabled and no human task is reported complete without its real evidence.
