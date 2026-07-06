#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const defaultFrameCount = 480;
const requiredDspLiveOperations = ["read-source", "write-output", "verify-output", "clear-output"];

function usage() {
  console.log(`Describe or verify a command-backed Loopwire DSP provider.

Usage:
  describe-dsp-provider.mjs [--state-file FILE] [--configuration-id ID] [--frame-count N] [--format json|tsv]
  describe-dsp-provider.mjs --configuration FILE [--frame-count N] [--format json|tsv]
  describe-dsp-provider.mjs --configuration FILE --provider-command COMMAND [--require-live-capability]
  describe-dsp-provider.mjs --configuration FILE --provider-command COMMAND --execute [--timeout-ms MS]

Options:
  --configuration FILE       Loopwire configuration export or raw configuration JSON.
  --state-file FILE          Persisted Loopwire state. Defaults to XDG config state.
  --configuration-id ID      Select a configuration from --state-file instead of the active one.
  --provider-command COMMAND DSP provider command for execute or capability checks.
  --require-live-capability  Probe provider capabilities and require supportsLiveGraph:true.
  --timeout-ms MS            Provider operation timeout. Default: 5000.
  --frame-count N            Bounded source frames requested from the provider. Default: 480.
  --execute                  Run provider apply and verify. Without this, the command is read-only.
  --format json|tsv          Output format. Default: json.
  --pretty                   Pretty-print JSON output.

The default plan mode never calls the provider command unless --require-live-capability is set.
Execute mode can mutate provider-owned host audio outputs.`);
}

function parseArgs(argv) {
  const parsed = {
    configurationFile: undefined,
    configurationId: undefined,
    execute: false,
    format: "json",
    frameCount: defaultFrameCount,
    pretty: false,
    providerCommand: undefined,
    requireLiveCapability: false,
    stateFile: defaultStateFile(),
    timeoutMs: 5000
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    switch (arg) {
      case "--":
        break;
      case "--configuration":
        parsed.configurationFile = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--configuration-id":
        parsed.configurationId = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--state-file":
        parsed.stateFile = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--provider-command":
        parsed.providerCommand = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--timeout-ms":
        parsed.timeoutMs = parsePositiveInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--frame-count":
        parsed.frameCount = parsePositiveInteger(requiredValue(argv, index, arg), arg);
        index += 1;
        break;
      case "--format":
        parsed.format = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--execute":
        parsed.execute = true;
        break;
      case "--require-live-capability":
        parsed.requireLiveCapability = true;
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

  if (parsed.configurationFile && parsed.configurationId) {
    throw new Error("--configuration-id can only be used with --state-file");
  }

  if (parsed.format !== "json" && parsed.format !== "tsv") {
    throw new Error(`Unsupported output format: ${parsed.format}`);
  }

  if (parsed.execute && !parsed.providerCommand) {
    throw new Error("--execute requires --provider-command");
  }

  if (parsed.requireLiveCapability && !parsed.providerCommand) {
    throw new Error("--require-live-capability requires --provider-command");
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

function parsePositiveInteger(value, flag) {
  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new Error(`${flag} must be a positive integer`);
  }

  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new Error(`${flag} is too large`);
  }

  return parsed;
}

function defaultStateFile() {
  const configHome = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  return join(configHome, "loopwire", "state.json");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const [core, audioHost] = await Promise.all([
    import("../packages/core/dist/index.js"),
    import("../packages/audio-host/dist/index.js")
  ]);
  const configuration = await loadConfiguration(args, core);
  const plan = core.createDspMixPlan(configuration);
  const operations = describeOperations(core, plan, args.frameCount);
  const providerCapability = args.requireLiveCapability
    ? await probeProviderCapability(audioHost, args)
    : undefined;
  const execution = args.execute
    ? await executeProvider(audioHost, args, configuration)
    : undefined;
  const capabilityOk = providerCapability ? providerCapability.ok === true : true;
  const payload = {
    ok: capabilityOk && (execution ? execution.ok : true),
    mode: args.execute ? "execute" : "plan",
    configurationId: configuration.id,
    configurationName: configuration.name,
    frameCount: args.frameCount,
    ...(args.providerCommand ? { providerCommand: args.providerCommand } : {}),
    ...(providerCapability ? { providerCapability } : {}),
    operations,
    ...(execution ? { execution } : {})
  };

  if (args.format === "tsv") {
    process.stdout.write(formatTsv(payload));
  } else {
    process.stdout.write(`${JSON.stringify(payload, null, args.pretty ? 2 : 0)}\n`);
  }

  if (!payload.ok) {
    process.exitCode = 1;
  }
}

function describeOperations(core, plan, frameCount) {
  const reads = core.listDspSourceRequests(plan, frameCount).map((request) => ({
    operation: "read-source",
    target: request.sourceId,
    label: request.sourceLabel,
    channels: request.channels,
    frames: frameCount
  }));
  const outputs = plan.outputs.flatMap((output) => [
    {
      operation: "write-output",
      target: output.outputId,
      label: output.outputLabel,
      channels: output.channels,
      frames: frameCount
    },
    {
      operation: "verify-output",
      target: output.outputId,
      label: output.outputLabel,
      channels: output.channels,
      frames: frameCount
    },
    {
      operation: "clear-output",
      target: output.outputId,
      label: output.outputLabel,
      channels: output.channels,
      frames: frameCount
    }
  ]);

  return [...reads, ...outputs];
}

async function probeProviderCapability(audioHost, args) {
  const result = await audioHost.createNodeCommandRunner().run(args.providerCommand, ["capabilities"], {
    timeoutMs: args.timeoutMs
  });

  if (result.exitCode !== 0) {
    return {
      ok: false,
      supportsLiveGraph: false,
      message: providerCapabilityMessage(result, "capabilities command failed")
    };
  }

  const raw = result.stdout.trim();
  if (!raw) {
    return {
      ok: false,
      supportsLiveGraph: false,
      message: providerCapabilityMessage(result, "capabilities command returned empty stdout")
    };
  }

  try {
    const payload = JSON.parse(raw);
    const supportsLiveGraph = Boolean(payload?.supportsLiveGraph === true);
    const missingOperations = missingDspLiveOperations(payload);
    const ok = supportsLiveGraph && missingOperations.length === 0;
    const message = !supportsLiveGraph
      ? "DSP provider does not declare supportsLiveGraph=true."
      : missingOperations.length > 0
        ? `DSP provider is missing required operation(s): ${missingOperations.join(", ")}`
        : undefined;

    return {
      ...payload,
      ok,
      supportsLiveGraph,
      ...(message ? { message } : {})
    };
  } catch {
    return {
      ok: false,
      supportsLiveGraph: false,
      message: providerCapabilityMessage(result, "capabilities command returned invalid JSON")
    };
  }
}

function providerCapabilityMessage(result, reason) {
  const detail = result.stderr.trim() || result.stdout.trim();
  return `DSP provider ${reason}${detail ? `: ${detail}` : ""}`;
}

function missingDspLiveOperations(payload) {
  const operations = Array.isArray(payload?.operations)
    ? new Set(payload.operations.filter((operation) => typeof operation === "string"))
    : new Set();

  return requiredDspLiveOperations.filter((operation) => !operations.has(operation));
}

async function executeProvider(audioHost, args, configuration) {
  const adapter = audioHost.createDspGraphRuntimeAdapter(
    audioHost.createDspRuntimeCommandPorts(audioHost.createNodeCommandRunner(), {
      command: args.providerCommand,
      timeoutMs: args.timeoutMs
    }),
    {
      mode: "apply",
      frameCount: args.frameCount
    }
  );
  const apply = await adapter.apply(configuration);
  const verify = apply.ok ? await adapter.verify(configuration) : undefined;
  const cleanup = apply.ok ? await adapter.unload(configuration) : undefined;
  const ok = Boolean(apply.ok && verify?.ok && cleanup?.ok);

  return {
    ok,
    apply,
    ...(verify ? { verify } : {}),
    ...(cleanup ? { cleanup } : {}),
    commandLog: adapter.commandLog
  };
}

async function loadConfiguration(args, core) {
  if (args.configurationFile) {
    return loadConfigurationFile(args.configurationFile, core);
  }

  const raw = await readFile(args.stateFile, "utf8");
  const restored = core.restoreState(raw);

  if (!restored.ok) {
    throw new Error(`Could not restore Loopwire state: ${restored.reason}`);
  }

  if (args.configurationId) {
    const configuration = restored.state.configurations.find((item) => item.id === args.configurationId);
    if (!configuration) {
      throw new Error(`Configuration not found in state: ${args.configurationId}`);
    }

    return configuration;
  }

  return core.getActiveConfiguration(restored.state);
}

async function loadConfigurationFile(path, core) {
  const raw = await readFile(path, "utf8");
  const value = JSON.parse(raw);
  const payload = isConfigurationExport(value)
    ? raw
    : JSON.stringify({
        kind: core.configurationExportKind,
        version: core.configurationExportVersion,
        configuration: value
      });
  const imported = core.importConfiguration(emptyState(core), payload, new Date(0).toISOString());

  if (!imported.ok) {
    throw new Error(`Could not read Loopwire configuration: ${imported.reason}`);
  }

  return imported.configuration;
}

function emptyState(core) {
  return {
    version: core.schemaVersion,
    configurations: [],
    hiddenMonitorIds: []
  };
}

function isConfigurationExport(value) {
  return Boolean(value && typeof value === "object" && value.kind === "loopwire.configuration" && value.version === 1);
}

function formatTsv(payload) {
  const rows = [
    ["operation", "target", "label", "channels", "frames"],
    ...payload.operations.map((operation) => [
      operation.operation,
      operation.target,
      operation.label,
      String(operation.channels),
      String(operation.frames)
    ])
  ];

  if (payload.execution) {
    rows.push(
      ["apply-result", payload.configurationId, payload.execution.apply.message ?? "", "", ""],
      [
        "verify-result",
        payload.configurationId,
        payload.execution.verify?.message ?? "not-run",
        "",
        ""
      ]
    );
  }

  if (payload.providerCapability) {
    rows.push([
      "provider-capability",
      payload.providerCommand,
      payload.providerCapability.supportsLiveGraph ? "supportsLiveGraph=true" : payload.providerCapability.message,
      "",
      ""
    ]);
  }

  return `${rows.map((row) => row.map(formatTsvCell).join("\t")).join("\n")}\n`;
}

function formatTsvCell(value) {
  return String(value).replace(/[\t\r\n]+/g, " ");
}

main().catch((error) => {
  if (error?.code === "ERR_MODULE_NOT_FOUND") {
    console.error("Loopwire packages are not built. Run: pnpm --filter @loopwire/core build && pnpm --filter @loopwire/audio-host build");
    process.exit(1);
  }

  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
