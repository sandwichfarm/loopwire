# Requirements: Loopwire

**Defined:** 2026-07-03
**Core Value:** World-class UX for real Linux audio routing.

## v1 Requirements

### Product UX

- [x] **UX-01**: User sees a polished desktop app shell with app title, backend state, configurations, routes, and monitors.
- [x] **UX-02**: App uses native window chrome; missing decorations are treated as environment bugs to report, not a mode to switch (custom-chrome fallback removed in the UI rebuild).
- [x] **UX-03**: User can hide and reveal monitors without deleting the underlying monitor.
- [x] **UX-04**: User-facing copy avoids raw backend jargon outside diagnostics and advanced settings.

### Audio Backend Compatibility

- [x] **BACKEND-01**: App detects available PipeWire, PulseAudio, JACK, and ALSA candidates.
- [x] **BACKEND-02**: App auto-selects one backend when exactly one viable backend exists.
- [x] **BACKEND-03**: App prompts the user when more than one viable backend exists.
- [x] **BACKEND-04**: User can change backend selection in settings.
- [x] **BACKEND-05**: Backend adapters expose capability, diagnostics, apply, verify, and rollback contracts.

### Configuration Runtime

- [x] **CONFIG-01**: User can create multiple named configurations with inputs, outputs, monitors, and routes.
- [x] **CONFIG-02**: Clicking a configuration unloads the active configuration and applies the selected configuration.
- [x] **CONFIG-03**: Selected configuration persists across shutdown and is selected/applied on next startup.
- [x] **CONFIG-04**: Invalid persisted state falls back safely without corrupting saved configurations.

### Linux Integration

- [x] **LINUX-01**: App supports common DE and WM environments without assuming one compositor.
- [x] **LINUX-02**: App provides a clear user-scoped start-on-boot path.
- [x] **LINUX-03**: Installer detects Linux architecture and package format without forcing system changes.
- [x] **LINUX-04**: Packaging path exists for curl installer, AUR, Nix flake, and future distro packages.

### Documentation and Website

- [x] **DOCS-01**: VitePress builds docs and the public website.
- [x] **DOCS-02**: Website includes above-the-fold title, subline, product screenshot, and installation instructions.
- [x] **DOCS-03**: Docs include backend support, architecture, install, troubleshooting, and start-on-boot guidance.
- [x] **DOCS-04**: Release notes and docs update with every user-visible release.

### Quality and Delivery

- [x] **QUAL-01**: Domain behavior has unit and property-style tests.
- [x] **QUAL-02**: CI runs install, typecheck, tests, builds, docs build, and script syntax checks.
- [x] **QUAL-03**: Continuous testing covers heavier Linux/audio checks where host runners are available.
- [x] **QUAL-04**: CD can deploy the VitePress website to Bunny.net from protected workflows.
- [x] **QUAL-05**: Helper script sets required GitHub secrets for Bunny.net deployment.

## v2 Requirements

Requirements for the next milestone.

### Production Routing

- [x] **ROUTE-01**: User can bind monitor endpoints to physical host sink names.
- [x] **ROUTE-02**: User can apply a configuration through an explicit live backend consent path.
- [x] **ROUTE-03**: PulseAudio compatibility routing can verify and roll back every host mutation it performs.
- [x] **ROUTE-04**: Native PipeWire routing can connect, verify, and remove configured existing graph links.
- [x] **ROUTE-05**: Route semantics support true per-edge gain/mute when one source targets multiple outputs.

### Release Proof

- [ ] **SHIP-01**: Published GitHub Release assets can be installed with signature verification.
- [ ] **SHIP-02**: At least one VM target captures install, launch, backend detection, and desktop screenshot evidence.
- [ ] **SHIP-03**: Release notes, support matrix, and install docs match the published artifact behavior.

## Future Requirements

- **PRO-01**: JACK bridge presets for professional audio workflows.
- **PRO-02**: Advanced channel remapping and per-route processing.
- **PRO-03**: Import/exportable support bundles with redaction.
- **PRO-04**: Distro-native packages beyond AUR and Nix.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Proprietary Loopback clone assets | Legal and product-integrity boundary |
| Cloud sync | Not required for local audio routing v1 |
| Raw audio logging | Privacy and storage risk |
| System-wide daemon requirement | User-scoped startup is safer for v1 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| UX-01..UX-04 | Phase 1, Phase 4 | Complete |
| BACKEND-01..BACKEND-05 | Phase 1, Phase 2 | Complete |
| CONFIG-01..CONFIG-04 | Phase 1, Phase 3 | Complete |
| LINUX-01..LINUX-04 | Phase 1, Phase 5 | Complete |
| DOCS-01..DOCS-04 | Phase 1, Phase 6 | Complete |
| QUAL-01..QUAL-05 | Phase 1, Phase 7 | Complete |
| ROUTE-01 | Phase 8 | Complete |
| ROUTE-02, ROUTE-03 | Phase 10 | Complete |
| ROUTE-04 | Phase 9 | Complete |
| ROUTE-05 | Phase 11 | Complete |
| SHIP-01..SHIP-03 | Phase 12 | Pending |

**Coverage:**
- v1 requirements: 26 total, 26 complete
- v2 milestone requirements: 8 total
- Mapped to phases: 34
- Unmapped: 0

## v0.3 Requirements (Seed Harvest)

### Endpoint Metadata

- [x] **META-01**: AudioEndpoint carries a kind (app, capture, system, pass-thru) populated by enumeration and persisted through schema migration.
- [x] **META-02**: Icons, add-menu grouping, and per-kind options (mute-when-capturing) derive from endpoint kind, not label heuristics.

### Multichannel Buses

- [x] **BUS-01**: The Output Channels add control offers mono, stereo, and quad bus creation with correct channel labels and cabling.

### Power-User Surfaces

- [x] **SURF-01**: Configurations can be exported and imported from the Settings dialog using the versioned JSON format.
- [x] **SURF-02**: A diagnostics surface shows backend capability reports and probe results on demand.
- [x] **SURF-03**: Sources, buses, and monitors expose a manual host-binding field in card Options for unlisted host ports.

### Provider Settings

- [ ] **PROV-01**: DSP provider command, mode, timeout, and frame count are configurable in Settings, persisted, and gate DSP backend availability.
- [ ] **PROV-02**: JACK provider command, timeout, delegate mode, and readiness delay are configurable in Settings and feed live apply and preflight readiness.

### End-to-End Harness

- [ ] **E2E-01**: A repeatable harness drives the built UI (WebDriver or DOM-level automation) through create/add/cable/toggle/delete flows and asserts outcomes.
- [ ] **E2E-02**: The harness runs from one documented command and is wired into the repo verification surface.

### v0.3 Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| META-01..META-02 | Phase 13 | Complete |
| BUS-01 | Phase 14 | Complete |
| SURF-01..SURF-03 | Phase 15 | Complete |
| PROV-01..PROV-02 | Phase 16 | Pending |
| E2E-01..E2E-02 | Phase 17 | Pending |

---
*Requirements defined: 2026-07-03*
*Last updated: 2026-07-04 after support bundle backend summaries*
