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
| `debian-xfce-pulseaudio` | Debian stable, Xfce, X11, native PulseAudio |
| `nixos-gnome-pipewire` | NixOS, GNOME, Wayland, PipeWire/WirePlumber |
| `fedora-sway-pipewire` | Fedora, Sway, Wayland, PipeWire/WirePlumber |

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

Check local VM prerequisites:

```bash
pnpm vm:doctor
```

Check prerequisites for one target and print the exact guest/host evidence handoff:

```bash
pnpm vm:doctor -- --target arch-hyprland-pipewire
```

Print a non-mutating host setup plan for every target:

```bash
pnpm vm:host-plan
```

Print the same plan for one target:

```bash
pnpm vm:host-plan -- --target fedora-sway-pipewire
```

Print the per-target guest plan:

```bash
pnpm vm:plan
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

Validate and keep the rendered files for one target:

```bash
bash scripts/vm-matrix.sh verify-cloud-init --target fedora-kde-jack --output /tmp/loopwire-vm-check
```

Debian and Ubuntu cloud-init guest commands install the project pnpm toolchain with
`sudo npm install -g pnpm@11.3.0` before running `pnpm install --frozen-lockfile`, because those apt bootstrap images
do not reliably provide pnpm as a distro package.

NixOS cloud-init guest commands run the evidence collector through `nix develop --command` so `pnpm`, Node, Rust,
OpenSSL, and WebKitGTK come from the project flake rather than an assumed global guest profile.

Generated VM state belongs under `.vm/`, which is ignored by git.

## Host Preflight

Run `pnpm vm:doctor -- --target <target>` before trying a guest. The command is intentionally non-mutating: it only
checks local tools, KVM access, and the target metadata.

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

## Launch Policy

`scripts/vm-matrix.sh launch` is dry-run by default. Without `--execute`, it does not require the image path to exist,
does not render cloud-init, and does not write `.vm/run`; it only prints the base image path, planned overlay/seed
paths, and QEMU command. Launching requires an operator-owned cloud image and the explicit `--execute` flag:

```bash
bash scripts/vm-matrix.sh launch \
  --target arch-hyprland-pipewire \
  --image /path/to/arch-cloud.qcow2 \
  --ssh-port 2222 \
  --execute
```

The launch command uses the target architecture to choose the QEMU system binary, for example `qemu-system-x86_64` for
current x86_64 targets. Use `--ssh-port` when port `2222` is already occupied or when running multiple target guests
side by side. The dry-run output prints the matching `collect-vm-evidence-ssh.sh --port ...` command so evidence pull
uses the same forwarded port. Future aarch64 targets should fail preflight unless `qemu-system-aarch64` is present.

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

`environment.json` is structured proof that the bundle was captured for the selected `vm/targets.tsv` row. The
verifier checks the target distro, desktop/session, audio stack, architecture, and observed guest environment. If SSH
does not expose the graphical session variables, run the collector from the desktop session or set
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

After verification passes, promote the support-matrix row through the guarded updater:

```bash
pnpm vm:promote-evidence -- \
  --target arch-hyprland-pipewire \
  --dry-run
pnpm vm:promote-evidence -- --target arch-hyprland-pipewire
```

The promotion tool runs `scripts/verify-vm-evidence.sh` before editing docs. It only changes rows from `Manual VM` to
`Verified`, and it no-ops if the row is already verified. Do not edit support-matrix status by hand after evidence
collection unless the promotion tool cannot run and the verifier command has passed.

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

`command-results.tsv` must show successful `pnpm-check`, `desktop-launch`, `audio-host-build`, `detect-audio`,
`ct-host-check`, and `autostart` commands, and each row must point to the expected non-empty log file. `screenshot.png`
must be a real PNG file. Text placeholders are rejected by the verifier. `environment.json` must match the selected
VM target row and the observed distro, desktop/session, and architecture.

## CI Boundary

The `VM Matrix` workflow validates:

- shell syntax for `scripts/vm-matrix.sh`,
- target metadata consistency,
- generated per-target validation plans.

It does not boot VMs. Real VM execution should run locally, on a dedicated workstation, or on self-hosted runners with
KVM, audio services, and desktop session support.
