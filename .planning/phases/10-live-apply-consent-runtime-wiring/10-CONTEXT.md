# Phase 10 Context: Live Apply Consent and Runtime Wiring

## Goal

Connect desktop configuration switching to selected host adapters while requiring explicit user consent before any live
host command can run.

## Constraints

- Startup restore must not mutate host audio without fresh session consent.
- Browser/dev preview must fail closed for live apply because no Tauri command bridge exists there.
- The desktop frontend must not import the Node command runner into the browser bundle.
- The host command bridge must use an allowlist and must not invoke a shell.

## Inputs

- Core runtime transaction contract: unload, apply, verify, rollback.
- Audio-host browser-safe runtime adapters for PulseAudio compatibility and native PipeWire.
- Existing Tauri shell.

## Acceptance

- Desktop has an explicit `Host apply` control with preview and live-armed states.
- Preview mode routes through selected host adapters without host mutation.
- Live mode requires Tauri and routes commands through an allowlisted bridge.
- Selected backend controls whether PipeWire or PulseAudio compatibility adapter is injected.
- Startup verification uses preview mode.
- Failure states remain visible through runtime status and note surfaces.
