# VM Matrix

Loopwire needs proof on more than one friendly developer machine. The VM matrix is the project-local compatibility
surface for distro, desktop, session, package manager, and audio-server coverage.

## Targets

Target metadata lives in `vm/targets.tsv`.

| Target | Coverage |
|--------|----------|
| `arch-hyprland-pipewire` | Arch Linux, Hyprland, Wayland, PipeWire/WirePlumber |
| `fedora-kde-pipewire` | Fedora, KDE Plasma, Wayland, PipeWire/WirePlumber |
| `fedora-kde-jack` | Fedora, KDE Plasma, Wayland, JACK |
| `ubuntu-gnome-pipewire` | Ubuntu LTS, GNOME, Wayland, PipeWire/PulseAudio compatibility |
| `ubuntu-gnome-pipewire-aarch64` | Ubuntu LTS, GNOME, Wayland, PipeWire/PulseAudio compatibility, AArch64 |
| `debian-xfce-pulseaudio` | Debian stable, Xfce, X11, native PulseAudio |
| `nixos-gnome-pipewire` | NixOS, GNOME, Wayland, PipeWire/WirePlumber |
| `fedora-sway-pipewire` | Fedora, Sway, Wayland, PipeWire/WirePlumber |
| `opensuse-kde-pipewire` | openSUSE Tumbleweed, KDE Plasma, Wayland, PipeWire/WirePlumber |

The matrix is intentionally metadata-first. It lets CI validate the target contract without pretending GitHub-hosted
runners can test nested desktop audio VMs.

## Commands

List targets:

```bash
pnpm vm:list
```

Validate metadata and rendered cloud-init handoffs:

```bash
pnpm verify:vm
```

`pnpm verify:vm` is still non-mutating. It validates the target matrix, renders cloud-init files, and renders the
launch TSV, SSH TSV, and operator runbook to a temporary directory. The verifier fails if any target is missing its
QEMU launch command, evidence pull command, port allocation, evidence directory, or runbook handoff.

Check local VM prerequisites:

```bash
pnpm vm:doctor
```

Summarize which target evidence bundles are missing, invalid, or verified:

```bash
pnpm vm:evidence-status
```

Check prerequisites for one target and print the exact guest/host evidence handoff:

```bash
pnpm vm:doctor -- --target arch-hyprland-pipewire
```

Print a non-mutating host setup plan for every target:

```bash
pnpm vm:host-plan
```

Print the exact local host package command and post-install verification command for one target:

```bash
pnpm vm:host-setup -- --family apt --target ubuntu-gnome-pipewire-aarch64
```

Print the same plan for one target:

```bash
pnpm vm:host-plan -- --target fedora-sway-pipewire
```

Print the per-target guest plan:

```bash
pnpm vm:plan
```

Print a dry-run QEMU launch command for one target and operator-owned image:

```bash
pnpm vm:launch -- --target arch-hyprland-pipewire --image /path/to/arch-cloud.qcow2
```

Render a dry-run launch TSV for every target:

```bash
pnpm vm:render-launch-plan -- \
  --all \
  --image-root /path/to/cloud-images \
  --start-port 2222 \
  --output .vm/launch-targets.tsv
```

Render cloud-init assets for a target:

```bash
bash scripts/vm-matrix.sh render-cloud-init --target arch-hyprland-pipewire
```

Render cloud-init assets for every target:

```bash
pnpm vm:render-cloud-init -- --all --output .vm/cloud-init
```

Validate rendered cloud-init and guest command handoffs without leaving files behind:

```bash
bash scripts/vm-matrix.sh verify-cloud-init
```

Validate rendered launch, SSH, and runbook handoffs without leaving files behind:

```bash
bash scripts/vm-matrix.sh verify-handoffs
```

Validate and keep the rendered files for one target:

```bash
bash scripts/vm-matrix.sh verify-cloud-init --target fedora-kde-jack --output /tmp/loopwire-vm-check
```

Debian and Ubuntu cloud-init guest commands install the project pnpm toolchain with
`sudo npm install -g pnpm@11.3.0` before running `pnpm install --frozen-lockfile`, because those apt bootstrap images
do not reliably provide pnpm as a distro package.

Non-Nix guest bootstrap commands install Rust plus the current Tauri Linux build prerequisites for that distro family,
including WebKitGTK 4.1 development packages. This keeps the generated `pnpm check` handoff honest now that the
workspace check includes `pnpm verify:tauri`.

openSUSE cloud-init guest commands use `zypper`, install the Tauri openSUSE prerequisite set, and bootstrap pinned
`pnpm` through npm before workspace validation.

NixOS cloud-init guest commands run the evidence collector through `nix develop --command` so `pnpm`, Node, Rust,
OpenSSL, and WebKitGTK come from the project flake rather than an assumed global guest profile.

Generated VM state belongs under `.vm/`, which is ignored by git.

## Host Preflight

Run `pnpm vm:doctor -- --target <target>` before trying a guest. The command is intentionally non-mutating: it only
checks local tools, KVM access, and the target metadata.

Run `pnpm vm:doctor -- --all` before a broad compatibility pass. It checks every `vm/targets.tsv` row with the same
architecture-specific prerequisites, prints `target-check=*` before each target block, and exits nonzero if any target
cannot be launched from the current host.

The output includes:

- `target=*` rows describing the selected distro, desktop, session, audio stack, and architecture,
- an architecture-specific QEMU command check such as `qemu-system-x86_64=present` or `qemu-system-x86_64=missing`,
- `qemu-img`, `ssh`, and `cloud-localds` availability,
- `kvm=available`, `kvm=present-but-not-user-accessible`, or `kvm=missing`,
- `host-install-hint=*` with the package-manager command that should satisfy the local preflight,
- `guest-bootstrap=*`, `guest-evidence-command=*`, and `host-pull-command=*` handoff rows.

Treat missing QEMU, missing `cloud-localds`, inaccessible KVM, or missing SSH as host setup work. The helper will not
install packages, adjust groups, download distro images, or start VMs for you.

A nonzero `vm:doctor` exit means the host is not ready yet. Read the emitted rows, apply the `host-install-hint=*`
outside automation, then rerun the same target preflight.

`pnpm vm:host-plan` is the cross-system planning surface. It prints required host tools, install hints for Arch,
Debian/Ubuntu, Fedora, and Nix shells, an operator-owned image policy, render commands, dry-run launch commands, and
the SSH evidence pull command for each VM target. It is safe to run in CI because it does not install packages, download
images, or start VMs.

`pnpm vm:evidence-status` is the read-only evidence inventory. It checks `.vm/evidence/<target>` for every target by
default, reports `status=missing`, `status=invalid`, or `status=verified`, and prints the verifier command plus the SSH
collector handoff for missing targets. Use `--target <target>` to inspect one row, `--evidence-root DIR` for copied
bundles, and `--require-published-release --release-tag <tag>` for final public release proof. The missing-evidence
collector handoff honors the same `--host`, `--user`, `--identity`, and `--start-port` fields as
`pnpm vm:render-ssh-plan`, assigning all-target ports in target order as `start-port + index * 10` and writing back to
the selected evidence root. Missing evidence is reported without failing the command; invalid evidence exits nonzero
because the bundle exists but does not satisfy the verifier. Screenshot evidence must be a decodable, non-interlaced PNG
with valid chunk CRCs, image data, and desktop-sized dimensions; header-only, truncated, or CRC-corrupt PNG placeholders are rejected.

`pnpm vm:host-setup` is the focused local setup surface. It prints `package-family=*`, a single `install-command=*`,
the required VM host tools, and the `verify-command=*` to run after package setup. Use `pnpm vm:host-setup -- --all`
before a full matrix pass; it prints both x86_64 and AArch64 QEMU tool requirements and the matching
`bash scripts/vm-matrix.sh doctor --all` verifier. It is dry-run only, rejects `--execute`, and never installs packages
for the operator.

Host setup hints are architecture-scoped. AArch64 targets add the package-family tool that provides
`qemu-system-aarch64`, including Fedora `qemu-system-aarch64` and openSUSE `qemu-arm`; all-target setup prints the
combined x86_64 plus AArch64 package set so `pnpm vm:doctor -- --all` can pass after the operator installs tools.

The GitHub VM workflow also runs `scripts/vm-matrix.sh verify-cloud-init`. That job is still non-mutating, but it
catches target-specific bootstrap drift for every distro family before an operator spends time launching a guest.

Pull evidence from a reachable guest over SSH:

```bash
pnpm vm:collect-ssh -- \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --port 2222 \
  --desktop-port 5199
```

The SSH collector is dry-run by default. It prints the guest collector, `scp`, and local verifier commands. Add
`--execute` only after the guest is reachable and the operator is ready to run validation inside the VM.

For a multi-system pass, generate a starter SSH plan with one target-scoped row per VM:

```bash
pnpm vm:render-ssh-plan -- \
  --all \
  --start-port 2222 \
  --desktop-port 5199 \
  --output .vm/ssh-targets.tsv
```

The generated plan uses unique forwarded SSH ports, target-scoped `.vm/evidence/<target>` output paths, and the TSV
schema accepted by `pnpm vm:collect-matrix`. Edit host, user, identity, desktop port, or screenshot command cells when a
guest is not reachable on the local forwarded default.

The plan format is still plain tab-separated text, so hand-authored rows remain valid:

```bash
cat > .vm/ssh-targets.tsv <<'TSV'
# target	host	port	user	identity	desktop_port	screenshot_command	local_output_dir
arch-hyprland-pipewire	127.0.0.1	2222	loopwire	-	5199	-	-
fedora-kde-pipewire	127.0.0.1	2322	loopwire	-	5199	-	-
ubuntu-gnome-pipewire-aarch64	127.0.0.1	2422	loopwire	/path/to/key	5199	-	-
TSV

pnpm vm:collect-matrix -- --plan .vm/ssh-targets.tsv
```

`scripts/collect-vm-matrix-evidence.sh` is also dry-run by default. It expands each row into an exact
`scripts/collect-vm-evidence-ssh.sh` command, keeps local evidence target-scoped under `.vm/evidence/<target>`, and
rejects unknown targets, duplicate targets, invalid ports, unsafe local output paths, and malformed release-smoke
options before touching a guest. Add `--require-all-targets` for final-release passes so a hand-edited plan that omits
any `vm/targets.tsv` row fails before SSH runs. Use `-` or an empty cell for defaults. The columns are:

| Column | Default |
|--------|---------|
| `target` | Required `vm/targets.tsv` id |
| `host` | Required SSH host |
| `port` | `2222` |
| `user` | `loopwire` |
| `identity` | No identity file |
| `desktop_port` | Collector default |
| `screenshot_command` | Collector auto-detect |
| `local_output_dir` | `.vm/evidence/<target>` |

Custom `local_output_dir` values may be absolute or relative, but they must include the target id as its own path
segment and must not contain `..`. This prevents a matrix row from copying evidence into a shared directory or escaping
the intended evidence tree.

After the dry-run looks right, run:

```bash
pnpm vm:collect-matrix -- --plan .vm/ssh-targets.tsv --execute
```

For the final release pass, pass the same published-release smoke flags once and the matrix collector forwards them to
every guest row:

```bash
pnpm vm:collect-matrix -- \
  --plan .vm/ssh-targets.tsv \
  --published-release-repo sandwichfarm/loopwire \
  --published-release-tag v0.1.0 \
  --release-public-key packaging/release-signing-public.pem \
  --require-published-release \
  --require-github-release-source \
  --require-all-targets \
  --execute
```

## Launch Policy

`pnpm vm:launch` wraps `scripts/vm-matrix.sh launch` and is dry-run by default. Without `--execute`, it does not
require the image path to exist, does not render cloud-init, and does not write `.vm/run`; it only prints the base image
path, planned overlay/seed paths, and QEMU command. Launching requires an operator-owned cloud image and the explicit
`--execute` flag:

```bash
pnpm vm:launch -- \
  --target arch-hyprland-pipewire \
  --image /path/to/arch-cloud.qcow2 \
  --ssh-port 2222 \
  --execute
```

For matrix passes, generate launch rows before opening terminals:

```bash
pnpm vm:render-launch-plan -- \
  --all \
  --image-root /path/to/cloud-images \
  --start-port 2222 \
  --output .vm/launch-targets.tsv
```

The launch plan is TSV with `target`, `image`, `image_format`, `firmware`, `ssh_port`, `memory`, `cpus`,
`launch_command`, and `evidence_pull_command` columns. It assigns deterministic ports in increments of 10, so the
launch row and evidence row stay aligned for each VM. The generated commands are dry-run launch commands. Add
`--execute` only after replacing image paths with operator-owned cloud images and adding AArch64 firmware paths where
needed.

For a single operator-facing checklist, render a markdown runbook from the same matrix metadata:

```bash
pnpm vm:render-runbook -- \
  --all \
  --image-root /path/to/cloud-images \
  --start-port 2222 \
  --output .vm/runbook.md
```

The runbook includes host setup and doctor commands, cloud-init rendering, deterministic dry-run launch commands,
target-scoped SSH evidence-pull commands, a final-release `pnpm vm:collect-matrix` command with published-release smoke
and all-target strictness, local evidence verification, dry-run support-matrix promotion commands, and AArch64 firmware
reminders. It does not download images, install packages, launch guests, copy evidence, or edit docs.

The launch command uses the target architecture to choose the QEMU system binary, for example `qemu-system-x86_64` for
x86_64 targets and `qemu-system-aarch64` for AArch64 targets. AArch64 launch dry-runs add the `virt` machine and
`max` CPU model, and `--execute` requires an operator-supplied UEFI firmware path with `--firmware /path/to/QEMU_EFI.fd`.
Use `--ssh-port` when port `2222` is already occupied or when running multiple target guests side by side. The dry-run
output prints the matching `collect-vm-evidence-ssh.sh --port ...` command so evidence pull uses the same forwarded
port.
Launch inputs fail before QEMU planning if `--ssh-port` is not a valid TCP port, `--memory` is outside `512..262144`
MiB, `--cpus` is outside `1..256`, or `--image-format` is not `qcow2` or `raw`. Keep unusual hypervisor layouts
operator-owned instead of weakening the shared matrix helper.

Do not download distro images, install virtualization packages, or start long-running VMs from automation without a
specific operator decision.

After the guest boots and SSH is reachable, run the host-side collector against the forwarded port:

```bash
bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --port 2222 \
  --desktop-port 5199 \
  --execute
```

This command runs `scripts/collect-vm-evidence.sh` inside the guest checkout, copies the evidence bundle back to
`.vm/evidence/<target>`, then verifies it locally with `scripts/verify-vm-evidence.sh`.
The SSH port and guest desktop smoke port must be valid TCP ports from 1 to 65535; invalid values fail before SSH,
Vite, or evidence collection starts.
Custom `--remote-output-dir` and `--local-output-dir` paths may be absolute or relative, but they must include the
target id as a path segment and must not contain parent traversal, so direct SSH collection cannot mix evidence from
multiple VM targets.
The SSH collector also forwards the published-release smoke options, so final proof can be collected without manually
retyping the in-guest command.

## Guest Evidence Collector

Inside a VM, run the collector from a checked-out Loopwire repo:

```bash
bash scripts/collect-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --output-dir .vm/evidence/arch-hyprland-pipewire
```

The collector writes the exact bundle verified by `scripts/verify-vm-evidence.sh`: `pnpm-check.log`,
`desktop-launch.log`, `audio-host-build.log`, `environment.json`, `detect-audio.json`, `ct-host-check.log`,
`autostart.log`, `support-bundle.log`, a nested `support-bundle/` directory, `screenshot.png`, `notes.md`, and
`command-results.tsv`. It also writes `vm-evidence-verify.log` for operator debugging.
The nested `support-bundle/support-bundle.json` must include a parsed `audio.backends` summary so VM evidence exposes
backend availability, route-control scope, per-edge gain/mute flags, and gaps without opening raw logs.
When a VM run is reproducing a JACK configuration, the same support bundle can include `jack-port-requirements.json`
and a parsed `jack` readiness summary with matched and missing ports by passing the saved Loopwire configuration or
state file to the collector.

For final release proof after signed release assets exist, make installed-release smoke part of the same guest bundle:

```bash
bash scripts/collect-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --output-dir .vm/evidence/arch-hyprland-pipewire \
  --published-release-repo sandwichfarm/loopwire \
  --published-release-tag v0.1.0 \
  --release-public-key packaging/release-signing-public.pem \
  --require-published-release \
  --require-github-release-source
```

That mode runs `scripts/verify-published-release.sh` inside the guest, records `published-release-smoke.log`, and makes
`scripts/verify-vm-evidence.sh --require-published-release --release-tag v0.1.0 --require-github-release-source`
reject bundles that did not install and run the signed artifact for that exact release from the GitHub Release surface.
It also writes `published-release.json`, which binds the VM bundle to the release tag and either the GitHub repo or
guest-visible release directory used for the smoke. Guest-visible release directories remain useful for pre-publish VM
smoke but cannot satisfy final support proof.

After every target bundle is collected, package the exact archive consumed by the final release proof workflow:

```bash
pnpm vm:package-evidence -- \
  --tag v0.1.0 \
  --evidence-root .vm/evidence \
  --all \
  --require-published-release \
  --output dist/release/loopwire-vm-evidence-v0.1.0.tar.gz
```

The packager verifies each selected target bundle before writing the deterministic `vm-evidence/<target>` archive
layout and a `vm-evidence/manifest.json` root manifest that binds the release tag, selected targets, and
published-release strictness. It then validates the finished tarball with `scripts/extract-safe-tar.sh` and verifies the
extracted manifest, so unsafe paths, link members, tag mismatches, or missing target declarations fail before the archive
can become final proof material. It also fails if any target is missing or lacks published-release smoke. Custom
`--output` paths can use temp directories for local rehearsal, but the basename must still be a validated
`loopwire-vm-evidence-<tag>*.tar.gz` release asset name and the path cannot contain traversal, URL syntax, glob
metacharacters, symlinks, or a directory target.

`environment.json` is structured proof that the bundle was captured for the selected `vm/targets.tsv` row. The
verifier checks the target distro, desktop/session, architecture, observed guest environment, and expected audio
backend availability from `detect-audio.json`. If SSH does not expose the graphical session variables, run the
collector from the desktop session or set
`LOOPWIRE_EVIDENCE_SESSION` and `LOOPWIRE_EVIDENCE_DESKTOP` to the observed guest values before collecting evidence.

The desktop launch smoke starts the Loopwire desktop shell through Vite on `127.0.0.1:5181`, checks that the shell
responds, records `desktop-launch.log`, and then shuts the server down. If that port is already in use, pass a different
one. The collector validates the port range before launching the desktop smoke.

```bash
bash scripts/collect-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --output-dir .vm/evidence/arch-hyprland-pipewire \
  --desktop-port 5199
```

Screenshots fail closed. If the guest does not have `grim`, `gnome-screenshot`, or `spectacle`, provide an explicit
capture path:

```bash
bash scripts/collect-vm-evidence.sh \
  --target debian-xfce-pulseaudio \
  --output-dir .vm/evidence/debian-xfce-pulseaudio \
  --screenshot-command 'xfce4-screenshooter -f -s "$LOOPWIRE_SCREENSHOT_PATH"'
```

## Guest Evidence

Each VM target should attach:

- `pnpm check` output,
- `pnpm detect:audio` JSON,
- `bash scripts/ct-host-check.sh` redacted output,
- `pnpm verify:autostart` output,
- redacted support bundle manifest and command ledger,
- desktop screenshot showing the shell under that DE/WM and session type,
- notes for missing audio tools, unavailable JACK, portal issues, or distro-specific package gaps.

Store evidence in a target-scoped directory, then verify the bundle before making support claims:

```bash
bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir .vm/evidence/arch-hyprland-pipewire
```

For the final publish gate, require installed-release evidence too:

```bash
bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir .vm/evidence/arch-hyprland-pipewire \
  --require-published-release \
  --release-tag v0.1.0
```

After verification passes, promote the support-matrix row through the guarded updater:

```bash
pnpm vm:promote-evidence -- \
  --target arch-hyprland-pipewire \
  --require-published-release \
  --release-tag v0.1.0 \
  --dry-run
pnpm vm:promote-evidence -- --target arch-hyprland-pipewire --require-published-release --release-tag v0.1.0
```

After a broader VM pass, promote every target that has verified evidence under the matrix evidence root:

```bash
pnpm vm:promote-evidence -- \
  --all \
  --evidence-root .vm/evidence \
  --require-published-release \
  --release-tag v0.1.0 \
  --dry-run
pnpm vm:promote-evidence -- --all --evidence-root .vm/evidence --require-published-release --release-tag v0.1.0
```

The promotion tool runs `scripts/verify-vm-evidence.sh` before editing docs. It only changes rows from `Manual VM` to
`Verified`, and it no-ops if the row is already verified. In `--all` mode, missing evidence directories are reported
and skipped while invalid evidence fails the command. Use `--require-published-release` with `--release-tag` for final
public release claims so promotion also proves installed-release smoke for the exact release. Do not edit
support-matrix status by hand after evidence collection unless the promotion tool cannot run and the matching verifier
command has passed.

Required files are:

- `pnpm-check.log`
- `desktop-launch.log`
- `audio-host-build.log`
- `environment.json`
- `detect-audio.json`
- `ct-host-check.log`
- `autostart.log`
- `support-bundle.log`
- `support-bundle/support-bundle.json`
- `support-bundle/command-results.tsv`
- `support-bundle/notes.md`
- `screenshot.png`
- `notes.md`
- `command-results.tsv`
- `published-release-smoke.log` when `--require-published-release` is used
- `published-release.json` when `--release-tag` is used

`command-results.tsv` must show successful `pnpm-check`, `desktop-launch`, `audio-host-build`, `detect-audio`,
`ct-host-check`, and `autostart` commands, and each row must point to the expected non-empty log file. `screenshot.png`
must be a real PNG file with PNG header dimensions of at least 320x200. Text placeholders and tiny placeholder images
are rejected by the verifier. `environment.json` must match the selected VM target row and the observed distro,
desktop/session, and architecture. `detect-audio.json` must report the expected target backend as available: PipeWire
targets require PipeWire, compatibility targets require PipeWire and PulseAudio, PulseAudio targets require PulseAudio,
and JACK targets require JACK. When `--require-published-release` is used, the ledger must also include a successful
`published-release-smoke` row. When `--release-tag` is used, `published-release.json` must match that exact tag. Final
release support checks also require `published-release.json` to record GitHub release source.
The nested `support-bundle/command-results.tsv` must also show successful quick-profile diagnostics for `detect-audio`,
`ct-host-check`, and `autostart-status`, with each row pointing to a non-empty log inside `support-bundle/`.

## CI Boundary

The `VM Matrix` workflow validates:

- shell syntax for `scripts/vm-matrix.sh`,
- target metadata consistency,
- generated per-target validation plans.

It does not boot VMs. Real VM execution should run locally, on a dedicated workstation, or on self-hosted runners with
KVM, audio services, and desktop session support.
