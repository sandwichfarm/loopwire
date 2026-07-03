# Phase 8 Context: Physical Monitor Device Binding

Loopwire already creates Loopwire-owned monitor sinks and loopbacks for PulseAudio compatibility. The next production
routing gap is allowing a monitor endpoint to target an existing physical host sink by name while preserving the safe
Loopwire-owned fallback path.

## Boundary

- `deviceName` is a generic endpoint field in the core model.
- The PulseAudio compatibility adapter interprets monitor `deviceName` values as pactl sink names.
- Validation must use fake command runners; no live host mutation.
- The desktop can expose a text target field until device enumeration exists.
