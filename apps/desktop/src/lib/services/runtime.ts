import { derived, get, writable } from "svelte/store";
import { invoke } from "@tauri-apps/api/core";
import { detectAudioBackends, type BackendCapabilityReport } from "@loopwire/audio-host/detectors";
import {
  createDspConfigurationRuntimeAdapter,
  createDspRuntimeCommandPorts,
  createJackGraphRuntimeAdapter,
  createJackVirtualPortCommandProvider,
  createPactlVirtualSinkRuntimeAdapter,
  createPipeWireGraphRuntimeAdapter,
  type CommandResult,
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
import { describeConfigurationSwitchPreflight } from "../../live-apply-preflight";
import type { DeviceStore } from "../stores/deviceStore";
import { createTauriCommandRunner, createUnavailableCommandRunner } from "./commandRunner";
import { withDspProviderCandidate, type ProviderSettingsService } from "./providerSettings";
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

export function createRuntimeService(
  deviceStore: DeviceStore,
  onError: (message: string) => void,
  providerSettings: ProviderSettingsService
) {
  const detectedCandidates = writable<readonly BackendCandidate[]>(fallbackBackendCandidates);
  /**
   * DSP has no host probe: its candidate availability follows the saved
   * provider settings live, so editing them in Settings updates the picker.
   */
  const backendCandidates = derived(
    [detectedCandidates, providerSettings.dspRestoreProviderReady],
    ([candidates, dspReady]) => withDspProviderCandidate(candidates, dspReady)
  );
  const capabilityReports = writable<readonly BackendCapabilityReport[]>([]);
  const detectionNote = writable("Browser preview uses packaged backend candidates; run the desktop shell for host detection.");
  /** What the most recent transaction actually ran as (informational). */
  const lastApplyMode = writable<HostApplyMode>("preview");
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
      detectedCandidates.set(fallbackBackendCandidates);
      return;
    }

    detectionNote.set("Detecting Linux audio backends.");

    try {
      const report = await detectAudioBackends(createTauriCommandRunner(), new Date(), "linux");
      detectedCandidates.set(report.candidates);
      capabilityReports.set(report.reports);
      const available = report.candidates.filter((candidate) => candidate.availability === "available");
      detectionNote.set(
        available.length === 0
          ? "No Linux audio backend probes succeeded."
          : `Detected ${available.length} available backend(s): ${available.map((candidate) => candidate.displayName).join(", ")}.`
      );

      const decision = selectBackend(get(backendCandidates), selectedBackend());
      if (decision.mode === "auto" && decision.backend.kind !== selectedBackend()) {
        await chooseBackend(decision.backend.kind);
      }
    } catch (error) {
      detectedCandidates.set(fallbackBackendCandidates);
      detectionNote.set(error instanceof Error ? `Backend detection failed: ${error.message}` : "Backend detection failed.");
    }
  }

  async function chooseBackend(kind: AudioBackendKind): Promise<boolean> {
    busy.set(true);
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
   * Host apply is automatic: a transaction runs live when the desktop shell,
   * a saved backend, and a passing preflight all line up; otherwise it runs
   * in preview and the returned reason says why live apply was skipped.
   */
  function resolveApplyMode(configuration: LoopwireConfiguration | undefined): {
    readonly mode: HostApplyMode;
    readonly skippedReason?: string;
  } {
    if (!hasTauriRuntime()) {
      return { mode: "preview", skippedReason: "live host apply requires the Loopwire desktop shell" };
    }

    const backend = selectedBackend();

    if (!backend) {
      return { mode: "preview", skippedReason: "no audio backend is saved yet (choose one in Settings)" };
    }

    if (!configuration) {
      return { mode: "preview", skippedReason: "no device is selected" };
    }

    if (configuration.enabled === false) {
      return { mode: "preview", skippedReason: "this device is turned off" };
    }

    // Preflight sees the same route muting the adapters will (Off endpoints),
    // so an Off source with a lowered volume does not block live apply.
    const preflight = describeConfigurationSwitchPreflight(
      { ...configuration, routes: routesWithOffEndpointsMuted(configuration) },
      backend,
      get(capabilityReports),
      displayBackendName,
      {
        dspProviderReady: get(providerSettings.dspRestoreProviderReady),
        jackProviderReady: get(providerSettings.jackLiveProviderReady)
      }
    );

    if (!preflight.ok) {
      return { mode: "preview", skippedReason: preflight.message };
    }

    return { mode: "live" };
  }

  let switchToken = 0;
  /** Device currently applied live on the host, if any. */
  let liveDeviceId: string | null = null;
  /**
   * Host transactions never interleave: concurrent switch/unload/re-apply
   * requests queue behind each other (a mid-flight apply racing a second one
   * corrupts node/port bookkeeping on the host).
   */
  let transactionQueue: Promise<unknown> = Promise.resolve();

  function enqueueTransaction<T>(run: () => Promise<T>): Promise<T> {
    const next = transactionQueue.then(run, run);
    transactionQueue = next.catch(() => undefined);
    return next;
  }

  /** Removes a device's Loopwire-owned host state (Off toggle, preview switches). */
  function unloadDevice(deviceId: string): Promise<boolean> {
    return enqueueTransaction(() => runUnloadDevice(deviceId));
  }

  async function runUnloadDevice(deviceId: string): Promise<boolean> {
    const target = currentState().configurations.find((configuration) => configuration.id === deviceId);
    const backend = selectedBackend();

    if (!target || !hasTauriRuntime() || !backend) {
      return true;
    }

    const hostAdapter = createHostAdapter(backend, "live", "switch");

    if (!hostAdapter) {
      return true;
    }

    busy.set(true);
    status.set("applying");
    note.set(`Removing ${target.name} from ${displayBackendName(backend)}.`);

    const result = await hostAdapter.unload(toHostRuntimeConfiguration(target));

    status.set(result.ok ? "verified" : "failed");
    note.set(result.message ?? (result.ok ? `Removed ${target.name} from the host.` : "Host unload failed."));
    busy.set(false);

    if (result.ok && liveDeviceId === deviceId) {
      liveDeviceId = null;
    }

    if (!result.ok) {
      onError(result.message ?? "Host unload failed.");
    }

    return result.ok;
  }

  /**
   * Runs the unload→apply→verify transaction for a device switch, live through
   * the saved backend whenever preflight passes. Transactions are queued so
   * they never interleave, and serialized by token: a superseded request
   * neither runs nor replaces the state of a newer selection.
   */
  function switchDevice(deviceId: string): Promise<boolean> {
    const token = ++switchToken;
    return enqueueTransaction(() => runSwitchDevice(deviceId, token));
  }

  async function runSwitchDevice(deviceId: string, token: number): Promise<boolean> {
    if (token !== switchToken) {
      return false;
    }

    const target = currentState().configurations.find((configuration) => configuration.id === deviceId);
    const { mode, skippedReason } = resolveApplyMode(target);

    // A preview switch away from a live-applied device must still take that
    // device's Loopwire-owned state off the host.
    if (mode === "preview" && liveDeviceId && liveDeviceId !== deviceId) {
      await runUnloadDevice(liveDeviceId);
    }

    if (mode === "preview" && liveDeviceId === deviceId && target?.enabled === false) {
      await runUnloadDevice(deviceId);
    }

    busy.set(true);
    status.set("applying");
    note.set(mode === "live" ? `Applying on ${displayBackendName(selectedBackend()!)}.` : "Switching in preview mode.");

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

    if (result.ok && mode === "live") {
      liveDeviceId = deviceId;
    }

    if (result.ok && mode === "preview" && skippedReason && hasTauriRuntime() && selectedBackend()) {
      // A backend is saved but this selection could not go live — say why.
      note.set(`Applied in preview only: ${skippedReason}`);
      onError(`Applied in preview only: ${skippedReason}`);
    }

    lastApplyMode.set(mode);
    busy.set(false);
    return result.ok;
  }

  /** Startup restore uses the same automatic live/preview rule as selection. */
  async function verifyStartup(): Promise<void> {
    if (!deviceStore.snapshot().configurations.length) {
      return;
    }

    const { mode } = resolveApplyMode(findActiveConfiguration(currentState()));

    status.set("applying");
    note.set(
      mode === "live"
        ? `Restoring the selected device on ${displayBackendName(selectedBackend()!)}.`
        : "Verifying the selected device in preview mode."
    );

    const result = await verifyStartupConfiguration(
      currentState(),
      adapterForBackend(selectedBackend(), mode),
      new Date().toISOString()
    );

    if (result.ok) {
      deviceStore.restoreSnapshot(result.state);

      if (mode === "live") {
        liveDeviceId = findActiveConfiguration(currentState())?.id ?? null;
      }
    }

    lastApplyMode.set(mode);
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

      // A saved-but-invalid JACK provider would render a broken restore unit.
      if (backend === "jack" && providerSettings.jackSnapshot().configured && !providerSettings.jackSnapshot().restoreReady) {
        onError(
          "JACK provider settings are invalid: timeout must be positive and the detached readiness delay must be zero or greater."
        );
        return;
      }
    }

    backgroundStartup.set(await runStartupAction(enabled ? "background_install" : "background_uninstall"));
  }

  /**
   * Saved provider settings ride along with `background_install` so the
   * user-scoped systemd unit restores through the same provider contract.
   */
  function backgroundStartupInvokeOptions(action: string): Record<string, string | number> {
    if (action !== "background_install") {
      return {};
    }

    const backend = selectedBackend();

    if (backend === "dsp") {
      const dsp = providerSettings.dspSnapshot();

      if (dsp.command) {
        return {
          dspProviderCommand: dsp.command,
          dspProviderMode: dsp.mode,
          dspProviderTimeoutMs: dsp.timeoutMs,
          ...(dsp.frameCount !== undefined ? { dspFrameCount: dsp.frameCount } : {})
        };
      }
    }

    if (backend === "jack") {
      const jack = providerSettings.jackSnapshot();

      if (jack.configured) {
        return {
          jackProviderCommand: jack.command,
          jackProviderTimeoutMs: jack.timeoutMs,
          jackProviderDelegateMode: jack.delegateMode,
          ...(jack.delegateMode === "detached" ? { jackProviderReadyDelayMs: jack.readyDelayMs } : {})
        };
      }
    }

    return {};
  }

  async function runStartupAction(action: string): Promise<StartupStatus | null> {
    try {
      const raw = await invoke<string>("manage_startup", { action, ...backgroundStartupInvokeOptions(action) });
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
    if (kind === "dsp") {
      return runDspOperation(operation, configuration, reason, mode);
    }

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

  /**
   * DSP is provider-backed: operations run only against saved live provider
   * settings, and live transactions re-verify the provider's `capabilities`
   * contract before any host apply.
   */
  async function runDspOperation(
    operation: "unload" | "apply" | "verify" | "rollback",
    configuration: LoopwireConfiguration,
    reason: RuntimeTransactionReason,
    mode: HostApplyMode
  ): Promise<HostRuntimeOperationResult> {
    const dsp = providerSettings.dspSnapshot();

    if (!dsp.restoreReady) {
      return { ok: true, message: `Preview-verified ${configuration.name} (DSP Provider host apply unavailable).` };
    }

    if (mode === "live") {
      const capability = await verifyDspLiveProviderCapability();

      if (!capability.ok) {
        return capability;
      }
    }

    const runner = mode === "live" ? createTauriCommandRunner() : createUnavailableCommandRunner();
    const adapter = createDspConfigurationRuntimeAdapter(
      createDspRuntimeCommandPorts(runner, { command: dsp.command, timeoutMs: dsp.timeoutMs }),
      {
        mode: mode === "live" ? "apply" : "dry-run",
        ...(dsp.frameCount !== undefined ? { frameCount: dsp.frameCount } : {})
      }
    );

    const result = await adapter[operation](
      { ...configuration, routes: routesWithOffEndpointsMuted(configuration) },
      {
        id: `dsp-${operation}-${configuration.id}`,
        reason,
        toConfigurationId: configuration.id,
        operations: [operation],
        createdAt: new Date().toISOString()
      }
    );

    if (mode === "preview" && !result.ok) {
      return {
        ok: true,
        message: `Preview noted DSP Provider gap: ${result.message ?? "unsupported host operation"}`
      };
    }

    return result;
  }

  /** Fail closed unless the live DSP provider proves the required graph contract. */
  async function verifyDspLiveProviderCapability(): Promise<HostRuntimeOperationResult> {
    const dsp = providerSettings.dspSnapshot();

    if (!dsp.restoreReady) {
      return {
        ok: false,
        message: "DSP live apply needs a saved live provider command, positive timeout, and valid frame count."
      };
    }

    const result = await createTauriCommandRunner().run(dsp.command, ["capabilities"], { timeoutMs: dsp.timeoutMs });

    return evaluateDspLiveCapabilityResult(result);
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
      const jack = providerSettings.jackSnapshot();
      return createJackGraphRuntimeAdapter(runner, {
        mode: hostMode,
        ...(jack.liveReady
          ? {
              virtualPortProvider: createJackVirtualPortCommandProvider(runner, {
                command: jack.command,
                timeoutMs: jack.timeoutMs,
                args: jack.args
              })
            }
          : {})
      });
    }

    // DSP runs through runDspOperation (provider-backed configuration adapter).
    return undefined;
  }

  return {
    backendCandidates,
    capabilityReports,
    detectionNote,
    lastApplyMode,
    status,
    note,
    activity,
    busy,
    startup,
    backgroundStartup,
    detectBackends,
    chooseBackend,
    switchDevice,
    unloadDevice,
    verifyStartup,
    refreshStartupStatus,
    setStartupEnabled,
    setBackgroundStartupEnabled
  };
}

export type RuntimeService = ReturnType<typeof createRuntimeService>;

const requiredDspLiveOperations = ["read-source", "write-output", "verify-output", "clear-output"] as const;

/**
 * Evaluates a DSP provider `capabilities` probe. Live host apply is refused
 * unless the provider declares `supportsLiveGraph:true` and every operation
 * needed for apply, verify, and rollback/unload.
 */
export function evaluateDspLiveCapabilityResult(result: CommandResult): HostRuntimeOperationResult {
  if (result.exitCode !== 0) {
    return {
      ok: false,
      message: `DSP live provider capability check failed: ${firstCommandLine(result) ?? `exit ${result.exitCode}`}`
    };
  }

  try {
    const payload = JSON.parse(result.stdout.trim()) as {
      readonly supportsLiveGraph?: unknown;
      readonly operations?: unknown;
    };

    if (payload.supportsLiveGraph !== true) {
      return {
        ok: false,
        message: "DSP live provider must declare supportsLiveGraph:true before desktop host apply can run."
      };
    }

    const operations = Array.isArray(payload.operations)
      ? new Set(payload.operations.filter((operation): operation is string => typeof operation === "string"))
      : new Set<string>();
    const missing = requiredDspLiveOperations.filter((operation) => !operations.has(operation));

    if (missing.length > 0) {
      return {
        ok: false,
        message: `DSP live provider is missing required operation(s): ${missing.join(", ")}.`
      };
    }

    return { ok: true, message: "DSP live provider capabilities verified." };
  } catch {
    return {
      ok: false,
      message: "DSP live provider capabilities returned invalid JSON."
    };
  }
}

function firstCommandLine(result: CommandResult): string | undefined {
  return firstNonEmptyLine(result.stderr) ?? firstNonEmptyLine(result.stdout);
}

function firstNonEmptyLine(value: string): string | undefined {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
}

/**
 * Routes touching an Off endpoint are marked muted so live apply disconnects
 * them instead of pretending an Off card still carries audio.
 */
export function routesWithOffEndpointsMuted(configuration: LoopwireConfiguration): LoopwireConfiguration["routes"] {
  const disabledEndpointIds = new Set(
    [...configuration.inputs, ...configuration.outputs, ...configuration.monitors]
      .filter((endpoint) => endpoint.enabled === false)
      .map((endpoint) => endpoint.id)
  );

  return configuration.routes.map((route) =>
    disabledEndpointIds.has(route.from) || disabledEndpointIds.has(route.to) ? { ...route, muted: true } : route
  );
}

/** Maps domain state to the host adapter contract. */
export function toHostRuntimeConfiguration(configuration: LoopwireConfiguration): HostRuntimeConfiguration {
  return {
    id: configuration.id,
    name: configuration.name,
    inputs: configuration.inputs,
    outputs: configuration.outputs,
    monitors: configuration.monitors,
    routes: routesWithOffEndpointsMuted(configuration)
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
