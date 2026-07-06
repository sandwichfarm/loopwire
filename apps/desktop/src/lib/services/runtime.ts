import { get, writable } from "svelte/store";
import { invoke } from "@tauri-apps/api/core";
import { detectAudioBackends, type BackendCapabilityReport } from "@loopwire/audio-host/detectors";
import {
  createJackGraphRuntimeAdapter,
  createPactlVirtualSinkRuntimeAdapter,
  createPipeWireGraphRuntimeAdapter,
  type HostRuntimeConfiguration,
  type HostRuntimeOperationResult,
  type MissingStreamVerificationMode
} from "@loopwire/audio-host/runtime";
import {
  applyBackendSelection,
  applyConfigurationSwitch,
  findActiveConfiguration,
  selectBackend,
  verifyStartupConfiguration,
  type AudioBackendKind,
  type BackendCandidate,
  type ConfigurationRuntimeAdapter,
  type ConfigurationRuntimeResult,
  type LoopwireConfiguration,
  type LoopwireState,
  type RuntimeLogEntry,
  type RuntimeTransactionReason
} from "@loopwire/core";
import { describeConfigurationSwitchPreflight, describeLiveApplyPreflight } from "../../live-apply-preflight";
import type { DeviceStore } from "../stores/deviceStore";
import { createTauriCommandRunner, createUnavailableCommandRunner } from "./commandRunner";
import { hasTauriRuntime } from "./statePersistence";

export type HostApplyMode = "preview" | "live";
export type RuntimeBadge = "ready" | "applying" | "verified" | "rolled_back" | "failed";

export interface StartupStatus {
  readonly enabled: boolean;
  readonly available: boolean;
  readonly path: string;
  readonly binary: string;
  readonly message: string;
}

const fallbackBackendCandidates: readonly BackendCandidate[] = [
  { kind: "pipewire", displayName: "PipeWire", availability: "available", priority: 10 },
  { kind: "pulseaudio", displayName: "PulseAudio", availability: "available", priority: 20 },
  { kind: "jack", displayName: "JACK", availability: "unavailable", priority: 30, reason: "JACK bridge not detected" },
  {
    kind: "alsa",
    displayName: "ALSA",
    availability: "unavailable",
    priority: 40,
    reason: "Direct ALSA fallback is not enabled"
  }
];

const previewAdapter: ConfigurationRuntimeAdapter = {
  unload: (configuration) => ({ ok: true, message: `Preview-unloaded ${configuration.name}.` }),
  apply: (configuration) => ({ ok: true, message: `Preview-staged ${configuration.name}.` }),
  verify: (configuration) => ({ ok: true, message: `Preview-verified ${configuration.name}.` }),
  rollback: (configuration) => ({ ok: true, message: `Preview-restored ${configuration.name}.` })
};

export function displayBackendName(kind: AudioBackendKind): string {
  const labels: Record<AudioBackendKind, string> = {
    pipewire: "PipeWire",
    pulseaudio: "PulseAudio",
    jack: "JACK",
    alsa: "ALSA",
    dsp: "DSP Provider"
  };

  return labels[kind];
}

export function createRuntimeService(deviceStore: DeviceStore, onError: (message: string) => void) {
  const backendCandidates = writable<readonly BackendCandidate[]>(fallbackBackendCandidates);
  const capabilityReports = writable<readonly BackendCapabilityReport[]>([]);
  const detectionNote = writable("Browser preview uses packaged backend candidates; run the desktop shell for host detection.");
  const applyMode = writable<HostApplyMode>("preview");
  const status = writable<RuntimeBadge>("ready");
  const note = writable("Preview runtime ready.");
  const activity = writable<readonly RuntimeLogEntry[]>([]);
  const busy = writable(false);
  const startup = writable<StartupStatus | null>(null);
  const backgroundStartup = writable<StartupStatus | null>(null);

  function currentState(): LoopwireState {
    return deviceStore.snapshot();
  }

  function selectedBackend(): AudioBackendKind | undefined {
    return currentState().selectedBackend;
  }

  async function detectBackends(): Promise<void> {
    if (!hasTauriRuntime()) {
      backendCandidates.set(fallbackBackendCandidates);
      return;
    }

    detectionNote.set("Detecting Linux audio backends.");

    try {
      const report = await detectAudioBackends(createTauriCommandRunner(), new Date(), "linux");
      backendCandidates.set(report.candidates);
      capabilityReports.set(report.reports);
      const available = report.candidates.filter((candidate) => candidate.availability === "available");
      detectionNote.set(
        available.length === 0
          ? "No Linux audio backend probes succeeded."
          : `Detected ${available.length} available backend(s): ${available.map((candidate) => candidate.displayName).join(", ")}.`
      );

      const decision = selectBackend(report.candidates, selectedBackend());
      if (decision.mode === "auto" && decision.backend.kind !== selectedBackend()) {
        await chooseBackend(decision.backend.kind);
      }
    } catch (error) {
      backendCandidates.set(fallbackBackendCandidates);
      detectionNote.set(error instanceof Error ? `Backend detection failed: ${error.message}` : "Backend detection failed.");
    }
  }

  async function chooseBackend(kind: AudioBackendKind): Promise<boolean> {
    busy.set(true);
    applyMode.set("preview");
    status.set("applying");
    note.set(`Verifying ${displayBackendName(kind)} in preview mode.`);

    const result = await applyBackendSelection(
      currentState(),
      kind,
      adapterForBackend(kind, "preview"),
      new Date().toISOString()
    );

    if (result.ok) {
      deviceStore.restoreSnapshot(result.state);
    }

    updateStatus(result);
    busy.set(false);

    if (!result.ok) {
      onError(result.reason);
    }

    return result.ok;
  }

  /**
   * Editing a configuration while live apply is armed disarms it: edits are
   * saved to Loopwire state first and must be re-verified on the host before
   * another live transaction runs.
   */
  function disarmForEdit(): boolean {
    if (get(applyMode) !== "live") {
      return false;
    }

    applyMode.set("preview");
    status.set("ready");
    note.set("Live apply was disarmed after a configuration edit; re-arm it to verify this change on the host.");
    return true;
  }

  function setApplyMode(mode: HostApplyMode): boolean {
    if (mode === "live") {
      if (!hasTauriRuntime()) {
        onError("Live host apply requires the Loopwire desktop shell.");
        return false;
      }

      const backend = selectedBackend();

      if (!backend) {
        onError("Choose a detected backend before arming live host apply.");
        return false;
      }

      const configuration = findActiveConfiguration(currentState());

      if (!configuration) {
        onError("Create a device before arming live host apply.");
        return false;
      }

      const capability = get(capabilityReports).find((report) => report.kind === backend);
      const preflight = describeLiveApplyPreflight(configuration, backend, displayBackendName, capability, {
        dspProviderReady: false,
        jackProviderReady: false
      });

      if (!preflight.ok) {
        onError(preflight.message);
        return false;
      }
    }

    applyMode.set(mode);
    status.set("ready");
    note.set(mode === "live" ? "Live host apply armed for the next device switch." : "Preview runtime ready.");
    return true;
  }

  let switchToken = 0;

  /**
   * Runs the unload→apply→verify transaction for a device switch. Switches are
   * serialized by token: a stale async result cannot replace the state or
   * status of a newer selection.
   */
  async function switchDevice(deviceId: string): Promise<boolean> {
    const token = ++switchToken;
    const mode = get(applyMode);

    if (mode === "live") {
      const target = currentState().configurations.find((configuration) => configuration.id === deviceId);
      const preflight = target
        ? describeConfigurationSwitchPreflight(target, selectedBackend(), get(capabilityReports), displayBackendName, {
            dspProviderReady: false
          })
        : undefined;

      if (preflight && !preflight.ok) {
        status.set("failed");
        note.set(preflight.message);
        onError(preflight.message);
        return false;
      }
    }

    busy.set(true);
    status.set("applying");
    note.set(mode === "live" ? "Switching with live host apply armed." : "Switching in preview mode.");

    let result: ConfigurationRuntimeResult;

    try {
      result = await applyConfigurationSwitch(
        currentState(),
        deviceId,
        adapterForBackend(selectedBackend(), mode),
        new Date().toISOString()
      );
    } catch (error) {
      if (token === switchToken) {
        busy.set(false);
        status.set("failed");
        const message = error instanceof Error ? error.message : "Device switch failed.";
        note.set(message);
        onError(message);
      }

      return false;
    }

    if (token !== switchToken) {
      return false;
    }

    if (result.ok) {
      deviceStore.restoreSnapshot(result.state);
    } else {
      onError(result.reason);
    }

    updateStatus(result);
    busy.set(false);
    return result.ok;
  }

  async function verifyStartup(): Promise<void> {
    if (!deviceStore.snapshot().configurations.length) {
      return;
    }

    status.set("applying");
    note.set("Verifying the selected device in preview mode.");

    const result = await verifyStartupConfiguration(
      currentState(),
      adapterForBackend(selectedBackend(), "preview"),
      new Date().toISOString()
    );

    if (result.ok) {
      deviceStore.restoreSnapshot(result.state);
    }

    updateStatus(result);
  }

  async function refreshStartupStatus(): Promise<void> {
    if (!hasTauriRuntime()) {
      startup.set(null);
      backgroundStartup.set(null);
      return;
    }

    startup.set(await runStartupAction("status"));
    backgroundStartup.set(await runStartupAction("background_status"));
  }

  async function setStartupEnabled(enabled: boolean): Promise<void> {
    startup.set(await runStartupAction(enabled ? "install" : "uninstall"));
  }

  async function setBackgroundStartupEnabled(enabled: boolean): Promise<void> {
    if (enabled) {
      const backend = selectedBackend();
      const available =
        backend && get(backendCandidates).some((candidate) => candidate.kind === backend && candidate.availability === "available");

      // Refuse to write a systemd unit that cannot restore audio.
      if (!available) {
        onError(
          backend
            ? `${displayBackendName(backend)} is saved but not currently detected; background restore stays off.`
            : "Choose and verify an audio backend before enabling background restore."
        );
        return;
      }
    }

    backgroundStartup.set(await runStartupAction(enabled ? "background_install" : "background_uninstall"));
  }

  async function runStartupAction(action: string): Promise<StartupStatus | null> {
    try {
      const raw = await invoke<string>("manage_startup", { action });
      return parseStartupStatus(raw);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Could not manage startup integration.";
      onError(message);
      return {
        enabled: false,
        available: false,
        path: "",
        binary: "",
        message
      };
    }
  }

  function updateStatus(result: ConfigurationRuntimeResult): void {
    status.set(result.status);
    note.set(result.ok ? (result.log.at(-1)?.message ?? "Verified in the app runtime.") : result.reason);
    activity.set(result.log);
  }

  function adapterForBackend(kind: AudioBackendKind | undefined, mode: HostApplyMode): ConfigurationRuntimeAdapter {
    if (!kind) {
      return previewAdapter;
    }

    return {
      unload: (configuration, plan) => runOperation(kind, "unload", configuration, plan.reason, mode),
      apply: (configuration, plan) => runOperation(kind, "apply", configuration, plan.reason, mode),
      verify: (configuration, plan) => runOperation(kind, "verify", configuration, plan.reason, mode),
      rollback: (configuration, plan) => runOperation(kind, "rollback", configuration, plan.reason, mode)
    };
  }

  async function runOperation(
    kind: AudioBackendKind,
    operation: "unload" | "apply" | "verify" | "rollback",
    configuration: LoopwireConfiguration,
    reason: RuntimeTransactionReason,
    mode: HostApplyMode
  ): Promise<HostRuntimeOperationResult> {
    const hostAdapter = createHostAdapter(kind, mode, reason);

    if (!hostAdapter) {
      return { ok: true, message: `Preview-verified ${configuration.name} (${displayBackendName(kind)} host apply unavailable).` };
    }

    const result = await hostAdapter[operation](toHostRuntimeConfiguration(configuration));

    if (mode === "preview" && !result.ok) {
      return {
        ok: true,
        message: `Preview noted ${displayBackendName(kind)} gap: ${result.message ?? "unsupported host operation"}`
      };
    }

    return result;
  }

  function createHostAdapter(kind: AudioBackendKind, mode: HostApplyMode, reason: RuntimeTransactionReason) {
    const runner = mode === "live" ? createTauriCommandRunner() : createUnavailableCommandRunner();
    const hostMode = mode === "live" ? "apply" : "dry-run";

    if (kind === "pipewire") {
      return createPipeWireGraphRuntimeAdapter(runner, { mode: hostMode });
    }

    if (kind === "pulseaudio") {
      const missingStreamVerification: MissingStreamVerificationMode = reason === "startup" ? "pending" : "fail";
      return createPactlVirtualSinkRuntimeAdapter(runner, { mode: hostMode, missingStreamVerification });
    }

    if (kind === "jack") {
      return createJackGraphRuntimeAdapter(runner, { mode: hostMode });
    }

    // DSP restore needs a configured live provider; its settings UI is not part
    // of this rebuild (documented deferral), so DSP stays preview-only here.
    return undefined;
  }

  return {
    backendCandidates,
    capabilityReports,
    detectionNote,
    applyMode,
    status,
    note,
    activity,
    busy,
    startup,
    backgroundStartup,
    detectBackends,
    chooseBackend,
    disarmForEdit,
    setApplyMode,
    switchDevice,
    verifyStartup,
    refreshStartupStatus,
    setStartupEnabled,
    setBackgroundStartupEnabled
  };
}

export type RuntimeService = ReturnType<typeof createRuntimeService>;

function toHostRuntimeConfiguration(configuration: LoopwireConfiguration): HostRuntimeConfiguration {
  return {
    id: configuration.id,
    name: configuration.name,
    inputs: configuration.inputs,
    outputs: configuration.outputs,
    monitors: configuration.monitors,
    routes: configuration.routes
  };
}

function parseStartupStatus(raw: string): StartupStatus {
  const parsed = JSON.parse(raw) as Partial<StartupStatus>;

  if (typeof parsed.enabled !== "boolean" || typeof parsed.path !== "string") {
    throw new Error("Startup status response is invalid.");
  }

  return {
    enabled: parsed.enabled,
    available: typeof parsed.available === "boolean" ? parsed.available : true,
    path: parsed.path,
    binary: typeof parsed.binary === "string" ? parsed.binary : "",
    message: typeof parsed.message === "string" ? parsed.message : "Startup status updated."
  };
}
