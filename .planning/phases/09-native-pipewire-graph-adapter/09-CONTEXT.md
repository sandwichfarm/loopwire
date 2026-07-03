# Phase 9 Context: Native PipeWire Graph Adapter

## Goal

Make PipeWire more than a detection backend by adding a guarded native route primitive that can connect existing graph
ports, verify those links, unload them, and roll back partial failures.

## Constraints

- Do not run live host graph mutation during automated validation.
- Use injected command runners so all behavior can be tested with fake PipeWire command output.
- Start with `pw-link` because it is present on this host and exposes stable list, link, and disconnect commands.
- Do not claim native virtual-node creation, monitor routing, or gain/mute controls until implemented.

## Inputs

- Existing `HostRuntimeConfiguration`, endpoint `deviceName`, and runtime operation result contracts.
- Local `pw-link --help` output confirms `-o`, `-i`, `-l`, direct link, and `-d` disconnect forms.
- Phase 8 added device names to monitor endpoints; Phase 9 uses the same field for routed PipeWire input/output ports.

## Acceptance

- Dry-run mode logs intended `pw-link` operations without calling the runner.
- Apply mode links configured existing output ports to input ports by endpoint `deviceName`.
- Verify mode fails when expected links are missing.
- Rollback/unload removes only configured links.
- Partial apply failure disconnects links created earlier in the same operation.
- Non-unity gain is rejected before host commands because plain `pw-link` cannot apply gain.
