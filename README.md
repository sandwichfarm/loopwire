# Loopwire

Loopwire is a Linux virtual audio routing app for PipeWire-first desktops. It is currently alpha-stage, with `v0.1.0`
as the first public version.

![Loopwire desktop patch bay screenshot](assets/product-screenshot.png)

Loopwire gives you named virtual devices with sources, output buses, monitor targets, and guarded backend apply
transactions. It keeps capability limits visible instead of pretending the host audio graph succeeded.

## Install

Install or upgrade with the platform-detecting installer:

```bash
curl -fsSL https://loopwire.app/install.sh | bash
```

The installer reports each step, verifies signed release checksums, and selects a matching native package, an
existing AUR helper, Nix, or a portable user install. It asks before package-manager changes. See the
[install guide](https://loopwire.app/docs/guide/install.html) for supported distro versions, requirements,
manual platform commands, upgrades, and a dry-run preview.

Contributors can still build from a checkout:

```bash
git clone https://github.com/sandwichfarm/loopwire
cd loopwire
pnpm install
pnpm check
```

The public `v0.1.0` release includes portable tarballs, AppImages, native packages, and signed checksums.

## Basic usage

1. Launch `loopwire` (or `pnpm --filter @loopwire/desktop dev` from a source checkout).
2. Create a new virtual device in the sidebar.
3. Add sources, an output bus, and a monitor target from the `+` menus.
4. Drag routes between ports and let Loopwire preview or apply the selected backend safely.

The default device starts as Pass-Thru -> Channels 1 & 2, so the first route is already visible.

## Guides

- [Install guide](https://loopwire.app/docs/guide/install.html)
- [Basic usage / first route](https://loopwire.app/docs/guide/basic-usage.html)
- [Configurations](https://loopwire.app/docs/guide/configurations.html)
- [Audio backends](https://loopwire.app/docs/guide/backends.html)
- [Start on boot](https://loopwire.app/docs/guide/start-on-boot.html)
- [Support matrix](https://loopwire.app/docs/guide/support-matrix.html)
- [Troubleshooting](https://loopwire.app/docs/guide/troubleshooting.html)
- [Developer architecture](https://loopwire.app/docs/developer/architecture.html)

## Status

Loopwire `v0.1.0` is the first alpha. PipeWire is the first-class path; PulseAudio and JACK have explicit compatibility
limits, and ALSA is detection-only. See the [support matrix](https://loopwire.app/docs/guide/support-matrix.html) before
relying on host apply. Native packages are direct downloads; APT, DNF/COPR, and OBS repositories are not yet published.

## Development

```bash
pnpm check
pnpm build:web
```

Release operators: [configure GitHub Actions variables and secrets](https://loopwire.app/docs/developer/github-actions-setup.html).
