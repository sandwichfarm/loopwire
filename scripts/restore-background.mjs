#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const validBackends = new Set(["pipewire", "pulseaudio", "jack", "dsp"]);
const validModes = new Set(["preview", "live"]);
const requiredDspLiveOperations = ["read-source", "write-output", "verify-output", "clear-output"];

function usage() {
  console.log(`Restore the persisted Loopwire configuration without opening the UI.

Usage:
  restore-background.mjs [--state-file FILE] [--backend pipewire|pulseaudio|jack|dsp] [--mode preview|live]
                         [--jack-provider-command COMMAND] [--jack-provider-timeout-ms MS]
                         [--jack-provider-delegate-mode foreground|detached] [--jack-provider-ready-delay-ms MS]
                         [--dsp-provider-command COMMAND] [--dsp-provider-timeout-ms MS]
                         [--dsp-provider-mode file-backed|live] [--dsp-frame-count FRAMES]
                         [--retry-pending-ms MS] [--retry-interval-ms MS] [--pretty]

Defaults:
  --state-file  $XDG_CONFIG_HOME/loopwire/state.json or ~/.config/loopwire/state.json
  --mode        preview
  --retry-pending-ms
                Live PulseAudio-only window for refreshing pending app-stream routes, default 0
  --retry-interval-ms
                PulseAudio pending refresh interval, default 1000
  --jack-provider-command
                Optional command that creates missing Loopwire-owned JACK ports during JACK live restore
  --jack-provider-timeout-ms
                Timeout for the JACK provider command, default 5000
  --jack-provider-delegate-mode
                How loopwire-jack-ports handles its live delegate, foreground or detached, default foreground
  --jack-provider-ready-delay-ms
                Detached JACK delegate readiness delay before re-probing jack_lsp, default provider behavior
  --dsp-provider-command
                Command-backed DSP provider used when --backend dsp is selected
  --dsp-provider-timeout-ms
                Timeout for DSP provider operations, default 5000
  --dsp-provider-mode
                DSP provider trust mode. Use file-backed for bundled preflight providers and live for real capture
                and playback providers. Live DSP restore requires live, default file-backed
  --dsp-frame-count
                Optional source frame count requested from the DSP provider

Preview mode runs the same startup plan through dry-run host adapters. Live mode mutates host audio through the
selected backend adapter and should only be used from an explicit user startup decision.`);
}

function parseArgs(argv) {
  const parsed = {
    stateFile: defaultStateFile(),
    backend: undefined,
    jackProviderCommand: undefined,
    jackProviderTimeoutMs: 5000,
    jackProviderDelegateMode: "foreground",
    jackProviderReadyDelayMs: undefined,
    dspProviderCommand: undefined,
    dspProviderTimeoutMs: 5000,
    dspProviderMode: "file-backed",
    dspFrameCount: undefined,
    mode: "preview",
    retryPendingMs: 0,
    retryIntervalMs: 1000,
    pretty: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    switch (arg) {
      case "--":
        break;
      case "--state-file":
        parsed.stateFile = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--backend":
        parsed.backend = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--mode":
        parsed.mode = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--jack-provider-command":
        parsed.jackProviderCommand = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--jack-provider-timeout-ms":
        parsed.jackProviderTimeoutMs = parsePositiveInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--jack-provider-delegate-mode":
        parsed.jackProviderDelegateMode = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--jack-provider-ready-delay-ms":
        parsed.jackProviderReadyDelayMs = parseNonNegativeInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--dsp-provider-command":
        parsed.dspProviderCommand = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--dsp-provider-timeout-ms":
        parsed.dspProviderTimeoutMs = parsePositiveInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--dsp-provider-mode":
        parsed.dspProviderMode = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--dsp-frame-count":
        parsed.dspFrameCount = parsePositiveInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--retry-pending-ms":
        parsed.retryPendingMs = parseNonNegativeInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--retry-interval-ms":
        parsed.retryIntervalMs = parsePositiveInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--pretty":
        parsed.pretty = true;
        break;
      case "-h":
      case "--help":
        usage();
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (parsed.backend !== undefined && !validBackends.has(parsed.backend)) {
    throw new Error(`Unsupported backend for background restore: ${parsed.backend}`);
  }

  if (!validModes.has(parsed.mode)) {
    throw new Error(`Unsupported restore mode: ${parsed.mode}`);
  }

  if (parsed.retryPendingMs > 0 && parsed.mode !== "live") {
    throw new Error("--retry-pending-ms requires --mode live");
  }

  if (!new Set(["foreground", "detached"]).has(parsed.jackProviderDelegateMode)) {
    throw new Error("--jack-provider-delegate-mode must be foreground or detached");
  }

  if (parsed.jackProviderDelegateMode !== "foreground" && !parsed.jackProviderCommand) {
    throw new Error("--jack-provider-delegate-mode requires --jack-provider-command");
  }

  if (parsed.jackProviderReadyDelayMs !== undefined) {
    if (!parsed.jackProviderCommand) {
      throw new Error("--jack-provider-ready-delay-ms requires --jack-provider-command");
    }

    if (parsed.jackProviderDelegateMode !== "detached") {
      throw new Error("--jack-provider-ready-delay-ms requires --jack-provider-delegate-mode detached");
    }
  }

  if (parsed.dspProviderCommand && parsed.backend !== "dsp") {
    throw new Error("--dsp-provider-command requires --backend dsp");
  }

  if (!new Set(["file-backed", "live"]).has(parsed.dspProviderMode)) {
    throw new Error("--dsp-provider-mode must be file-backed or live");
  }

  if (parsed.backend === "dsp" && !parsed.dspProviderCommand) {
    throw new Error("--backend dsp requires --dsp-provider-command");
  }

  if (parsed.dspProviderMode !== "file-backed" && !parsed.dspProviderCommand) {
    throw new Error("--dsp-provider-mode requires --dsp-provider-command");
  }

  if (parsed.backend === "dsp" && parsed.mode === "live" && parsed.dspProviderMode !== "live") {
    throw new Error("--backend dsp --mode live requires --dsp-provider-mode live");
  }

  if (parsed.dspFrameCount !== undefined && !parsed.dspProviderCommand) {
    throw new Error("--dsp-frame-count requires --dsp-provider-command");
  }

  if (parsed.dspProviderCommand && parsed.jackProviderCommand) {
    throw new Error("--dsp-provider-command cannot be combined with --jack-provider-command");
  }

  return parsed;
}

function requiredValue(argv, index, flag) {
  const value = argv[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }

  return value;
}

function parseNonNegativeInteger(value, flag) {
  if (!/^\d+$/.test(value)) {
    throw new Error(`${flag} must be a non-negative integer`);
  }

  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error(`${flag} is too large`);
  }

  return parsed;
}

function parsePositiveInteger(value, flag) {
  const parsed = parseNonNegativeInteger(value, flag);
  if (parsed === 0) {
    throw new Error(`${flag} must be greater than zero`);
  }

  return parsed;
}

function defaultStateFile() {
  const configHome = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  return join(configHome, "loopwire", "state.json");
}

function restoreStateRecoveryGuidance() {
  return "Open Loopwire once, choose a configuration, and enable Restore on boot again.";
}

async function readPersistedStateFile(stateFile) {
  try {
    return await readFile(stateFile, "utf8");
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Could not read persisted Loopwire state at ${stateFile}: ${detail}. ` +
        restoreStateRecoveryGuidance()
    );
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rawState = await readPersistedStateFile(args.stateFile);
  const [{ getActiveConfiguration, restoreState, selectBackend, verifyStartupConfiguration }, audioHost] = await Promise.all([
    import("../packages/core/dist/index.js"),
    import("../packages/audio-host/dist/index.js")
  ]);

  const restored = restoreState(rawState);

  if (!restored.ok) {
    throw new Error(
      `Could not restore persisted Loopwire state at ${args.stateFile}: ${restored.reason}. ` +
        restoreStateRecoveryGuidance()
    );
  }

  const runner = audioHost.createNodeCommandRunner();
  const detection = await audioHost.detectAudioBackends(runner);
  const selectedBackend = selectRestoreBackend({
    requestedBackend: args.backend,
    persistedBackend: restored.state.selectedBackend,
    detection,
    selectBackend,
    mode: args.mode
  });
  validateResolvedRestoreBackend(selectedBackend, args);
  const dspProviderCapability = await verifyDspProviderCapability(runner, selectedBackend, args);
  const adapter = createRuntimeAdapter(audioHost, runner, selectedBackend, args.mode, args);
  const result = await verifyStartupConfiguration(restored.state, adapter, new Date().toISOString());
  const pendingStreamRefresh = await refreshPendingPulseAudioRoutes({
    adapter,
    backend: selectedBackend,
    configuration: getActiveConfiguration(result.state),
    mode: args.mode,
    retryIntervalMs: args.retryIntervalMs,
    retryPendingMs: args.retryPendingMs,
    result
  });
  const ok = result.ok && !pendingStreamRefresh.failure;
  const failureReason = pendingStreamRefresh.failure ?? (result.ok ? undefined : result.reason);
  const payload = {
    ok,
    status: pendingStreamRefresh.failure ? "failed" : result.status,
    mode: args.mode,
    backend: selectedBackend,
    ...(args.jackProviderCommand && selectedBackend === "jack"
      ? {
          jackVirtualPortProvider: args.jackProviderCommand,
          jackVirtualPortProviderMode: args.jackProviderDelegateMode,
          ...(args.jackProviderReadyDelayMs !== undefined
            ? { jackVirtualPortProviderReadyDelayMs: args.jackProviderReadyDelayMs }
            : {})
        }
      : {}),
    ...(selectedBackend === "dsp"
      ? {
          dspProviderCommand: args.dspProviderCommand,
          dspProviderMode: args.dspProviderMode,
          ...(dspProviderCapability ? { dspProviderCapability } : {}),
          ...(args.dspFrameCount !== undefined ? { dspFrameCount: args.dspFrameCount } : {})
        }
      : {}),
    stateFile: args.stateFile,
    activeConfigurationId: result.state.activeConfigurationId,
    appliedAt: result.state.appliedAt,
    plan: result.plan,
    log: result.log,
    ...(pendingStreamRefresh.attempts.length > 0
      ? {
          pendingStreamRefresh: {
            windowMs: args.retryPendingMs,
            intervalMs: args.retryIntervalMs,
            cleared: pendingStreamRefresh.cleared,
            attempts: pendingStreamRefresh.attempts
          }
        }
      : {}),
    ...(failureReason ? { reason: failureReason } : {})
  };

  console.log(JSON.stringify(payload, null, args.pretty ? 2 : 0));

  if (!ok) {
    process.exitCode = 1;
  }
}

function selectRestoreBackend({ requestedBackend, persistedBackend, detection, selectBackend, mode }) {
  const backend = requestedBackend ?? persistedBackend;

  if (backend) {
    if (mode === "preview") {
      return backend;
    }

    if (backend === "dsp") {
      return backend;
    }

    const candidate = detection.candidates.find((item) => item.kind === backend);
    if (!candidate || candidate.availability !== "available") {
      throw new Error(
        `Selected backend is not available for background restore: ${backend}. ${backgroundRestoreBackendGuidance()}`
      );
    }

    return backend;
  }

  const decision = selectBackend(detection.candidates);
  if (decision.mode === "auto") {
    return decision.backend.kind;
  }

  if (decision.mode === "prompt") {
    const names = decision.candidates.map((candidate) => candidate.displayName).join(", ");
    throw new Error(
      `Multiple backends are available (${names}); choose and persist one before enabling background restore. ` +
        backgroundRestoreBackendGuidance()
    );
  }

  throw new Error(decision.reason);
}

function backgroundRestoreBackendGuidance() {
  return "Open Loopwire, use Settings > Audio backend to save a verified backend, then re-run Restore on boot.";
}

function validateResolvedRestoreBackend(selectedBackend, args) {
  if (selectedBackend !== "dsp") {
    return;
  }

  if (!args.dspProviderCommand) {
    throw new Error(
      "DSP background restore requires --dsp-provider-command after resolving the persisted backend. " +
        "Use preview with an explicit provider command for rehearsals, or configure a real live DSP provider."
    );
  }

  if (args.mode === "live" && args.dspProviderMode !== "live") {
    throw new Error("--backend dsp --mode live requires --dsp-provider-mode live");
  }
}

async function verifyDspProviderCapability(runner, backend, args) {
  if (backend !== "dsp" || args.mode !== "live" || args.dspProviderMode !== "live") {
    return undefined;
  }

  const result = await runner.run(args.dspProviderCommand, ["capabilities"], {
    timeoutMs: args.dspProviderTimeoutMs
  });

  if (result.exitCode !== 0) {
    throw new Error(providerCapabilityFailure(result, "capabilities command failed"));
  }

  const raw = result.stdout.trim();
  if (!raw) {
    throw new Error(providerCapabilityFailure(result, "capabilities command returned empty stdout"));
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    throw new Error(providerCapabilityFailure(result, "capabilities command returned invalid JSON"));
  }

  if (!payload || typeof payload !== "object" || payload.supportsLiveGraph !== true) {
    const providerKind =
      payload && typeof payload === "object" && typeof payload.providerKind === "string"
        ? ` (${payload.providerKind})`
        : "";
    throw new Error(
      `DSP live restore requires a provider that declares supportsLiveGraph=true${providerKind}. ` +
        "Use preview mode for file-backed providers or configure a real live DSP provider."
    );
  }

  const missingOperations = missingDspLiveOperations(payload);
  if (missingOperations.length > 0) {
    throw new Error(
      `DSP live restore provider is missing required operation(s): ${missingOperations.join(", ")}. ` +
        "Live providers must declare the read, write, verify, and clear operations Loopwire calls."
    );
  }

  return payload;
}

function providerCapabilityFailure(result, reason) {
  const detail = result.stderr.trim() || result.stdout.trim();
  return `DSP live restore provider ${reason}: ${result.command} capabilities${detail ? `: ${detail}` : ""}`;
}

function missingDspLiveOperations(payload) {
  const operations = Array.isArray(payload.operations)
    ? new Set(payload.operations.filter((operation) => typeof operation === "string"))
    : new Set();

  return requiredDspLiveOperations.filter((operation) => !operations.has(operation));
}

function createRuntimeAdapter(audioHost, runner, backend, mode, options) {
  const hostMode = mode === "live" ? "apply" : "dry-run";
  const adapter = createHostAdapter(audioHost, runner, backend, hostMode, options);
  const runtimeAdapter = {
    unload: (configuration) => adapter.unload(toHostRuntimeConfiguration(configuration)),
    apply: (configuration) => adapter.apply(toHostRuntimeConfiguration(configuration)),
    verify: (configuration) => adapter.verify(toHostRuntimeConfiguration(configuration)),
    rollback: (configuration) => adapter.rollback(toHostRuntimeConfiguration(configuration))
  };

  if (typeof adapter.refreshRoutes === "function") {
    return {
      ...runtimeAdapter,
      refreshRoutes: (configuration) => adapter.refreshRoutes(toHostRuntimeConfiguration(configuration))
    };
  }

  return runtimeAdapter;
}

function createHostAdapter(audioHost, runner, backend, mode, options) {
  if (backend === "dsp") {
    return audioHost.createDspGraphRuntimeAdapter(
      audioHost.createDspRuntimeCommandPorts(runner, {
        command: options.dspProviderCommand,
        timeoutMs: options.dspProviderTimeoutMs
      }),
      {
        mode,
        ...(options.dspFrameCount !== undefined ? { frameCount: options.dspFrameCount } : {})
      }
    );
  }

  if (backend === "pipewire") {
    return audioHost.createPipeWireGraphRuntimeAdapter(runner, { mode });
  }

  if (backend === "pulseaudio") {
    return audioHost.createPactlVirtualSinkRuntimeAdapter(runner, {
      mode,
      missingStreamVerification: "pending"
    });
  }

  if (backend === "jack") {
    const virtualPortProvider = options.jackProviderCommand
      ? audioHost.createJackVirtualPortCommandProvider(runner, {
          command: options.jackProviderCommand,
          timeoutMs: options.jackProviderTimeoutMs,
          args: jackProviderWrapperArgs(options)
        })
      : undefined;

    return audioHost.createJackGraphRuntimeAdapter(runner, {
      mode,
      ...(virtualPortProvider ? { virtualPortProvider } : {})
    });
  }

  throw new Error(`Background restore does not support backend: ${backend}`);
}

function jackProviderWrapperArgs(options) {
  const args = [];

  if (options.jackProviderDelegateMode === "detached") {
    args.push("--delegate-mode", "detached");

    if (options.jackProviderReadyDelayMs !== undefined) {
      args.push("--ready-delay-ms", String(options.jackProviderReadyDelayMs));
    }
  }

  return args;
}

function toHostRuntimeConfiguration(configuration) {
  return {
    id: configuration.id,
    name: configuration.name,
    inputs: configuration.inputs,
    outputs: configuration.outputs,
    monitors: configuration.monitors,
    routes: configuration.routes
  };
}

async function refreshPendingPulseAudioRoutes({
  adapter,
  backend,
  configuration,
  mode,
  retryIntervalMs,
  retryPendingMs,
  result
}) {
  if (
    !result.ok ||
    backend !== "pulseaudio" ||
    mode !== "live" ||
    retryPendingMs === 0 ||
    !logHasPendingPulseAudioStreams(result.log)
  ) {
    return { attempts: [], cleared: false };
  }

  if (typeof adapter.refreshRoutes !== "function") {
    return {
      attempts: [],
      cleared: false,
      failure: "PulseAudio pending stream retry is unavailable for this adapter."
    };
  }

  const attempts = [];
  const startedAt = Date.now();
  const deadline = startedAt + retryPendingMs;

  while (Date.now() < deadline) {
    const remainingMs = Math.max(0, deadline - Date.now());
    const waitMs = Math.min(retryIntervalMs, remainingMs);
    if (waitMs > 0) {
      await sleep(waitMs);
    }

    const attempt = attempts.length + 1;
    const refreshed = await adapter.refreshRoutes(configuration);
    const verified = refreshed.ok ? await adapter.verify(configuration) : undefined;
    attempts.push({
      attempt,
      waitedMs: Date.now() - startedAt,
      refreshed: operationSummary(refreshed),
      ...(verified ? { verified: operationSummary(verified) } : {})
    });

    if (!refreshed.ok) {
      return {
        attempts,
        cleared: false,
        failure: refreshed.message ?? "PulseAudio pending stream route refresh failed."
      };
    }

    if (verified && !verified.ok) {
      return {
        attempts,
        cleared: false,
        failure: verified.message ?? "PulseAudio pending stream verification failed."
      };
    }

    if (verified && !operationHasPendingPulseAudioStreams(verified)) {
      return { attempts, cleared: true };
    }
  }

  return { attempts, cleared: false };
}

function logHasPendingPulseAudioStreams(log) {
  return log.some((entry) => entry.ok && typeof entry.message === "string" && entry.message.includes(pendingStreamPrefix));
}

function operationHasPendingPulseAudioStreams(result) {
  return result.ok && typeof result.message === "string" && result.message.includes(pendingStreamPrefix);
}

function operationSummary(result) {
  return {
    ok: result.ok,
    ...(result.message ? { message: result.message } : {})
  };
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

const pendingStreamPrefix = "Pending matching PulseAudio stream(s)";

main().catch((error) => {
  console.error(`restore-background: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
