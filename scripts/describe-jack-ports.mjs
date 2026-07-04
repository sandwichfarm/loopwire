#!/usr/bin/env node
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

function usage() {
  console.log(`Describe JACK ports required by a Loopwire configuration.

Usage:
  describe-jack-ports.mjs [--state-file FILE] [--configuration-id ID] [--format json|tsv]
  describe-jack-ports.mjs --configuration FILE [--format json|tsv]
  describe-jack-ports.mjs --configuration FILE --verify [--ports-file FILE]

Options:
  --configuration FILE       Loopwire configuration export or raw configuration JSON.
  --state-file FILE          Persisted Loopwire state. Defaults to XDG config state.
  --configuration-id ID      Select a configuration from --state-file instead of the active one.
  --client-prefix PREFIX     Prefix for deterministic Loopwire-owned JACK clients. Default: loopwire.
  --loopwire-owned-only      Show only unbound endpoints that need pre-existing Loopwire-owned JACK ports.
  --verify                   Check whether the required ports exist. Uses jack_lsp unless --ports-file is provided.
  --ports-file FILE          Newline-delimited jack_lsp-style port list for deterministic verification.
  --format json|tsv          Output format. Default: json.
  --pretty                   Pretty-print JSON output.

The command never mutates JACK. Verification only reads jack_lsp output or a supplied port list.`);
}

function parseArgs(argv) {
  const parsed = {
    clientPrefix: "loopwire",
    configurationFile: undefined,
    configurationId: undefined,
    format: "json",
    loopwireOwnedOnly: false,
    portsFile: undefined,
    pretty: false,
    stateFile: defaultStateFile(),
    verify: false
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
      case "--client-prefix":
        parsed.clientPrefix = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--format":
        parsed.format = requiredValue(argv, index, arg);
        index += 1;
        break;
      case "--loopwire-owned-only":
        parsed.loopwireOwnedOnly = true;
        break;
      case "--ports-file":
        parsed.portsFile = requiredValue(argv, index, arg);
        parsed.verify = true;
        index += 1;
        break;
      case "--pretty":
        parsed.pretty = true;
        break;
      case "--verify":
        parsed.verify = true;
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

  return parsed;
}

function requiredValue(argv, index, flag) {
  const value = argv[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }

  return value;
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
  const allRequirements = audioHost.describeJackPortRequirements(configuration, {
    clientPrefix: args.clientPrefix
  });
  const requirements = args.loopwireOwnedOnly
    ? allRequirements.filter((requirement) => requirement.source === "loopwire-owned")
    : allRequirements;
  const verification = args.verify
    ? audioHost.describeJackPortReadiness(configuration, await readJackPorts(args), {
        clientPrefix: args.clientPrefix
      })
    : undefined;
  const payload = {
    configurationId: configuration.id,
    configurationName: configuration.name,
    clientPrefix: args.clientPrefix,
    requirements: verification
      ? filterVerifiedRequirements(verification.requirements, args.loopwireOwnedOnly)
      : requirements,
    ...(verification
      ? {
          ok: filteredVerificationOk(verification.requirements, args.loopwireOwnedOnly),
          portSource: args.portsFile ? "file" : "jack_lsp",
          portCount: verification.portCount,
          missingCount: filteredMissingCount(verification.requirements, args.loopwireOwnedOnly)
        }
      : {})
  };

  if (args.format === "tsv") {
    process.stdout.write(formatTsv(payload, args.verify));
    if (verification && !payload.ok) {
      process.exitCode = 1;
    }
    return;
  }

  process.stdout.write(`${JSON.stringify(payload, null, args.pretty ? 2 : 0)}\n`);

  if (verification && !payload.ok) {
    process.exitCode = 1;
  }
}

async function readJackPorts(args) {
  if (args.portsFile) {
    return parsePortList(await readFile(args.portsFile, "utf8"));
  }

  try {
    const result = await execFileAsync("jack_lsp", []);
    return parsePortList(result.stdout);
  } catch (error) {
    const detail = error?.stderr || error?.message || String(error);
    throw new Error(`Could not list JACK ports with jack_lsp: ${firstLine(detail)}`);
  }
}

function parsePortList(raw) {
  return raw.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

function filterVerifiedRequirements(requirements, loopwireOwnedOnly) {
  return loopwireOwnedOnly
    ? requirements.filter((requirement) => requirement.source === "loopwire-owned")
    : requirements;
}

function filteredVerificationOk(requirements, loopwireOwnedOnly) {
  return filterVerifiedRequirements(requirements, loopwireOwnedOnly).every((requirement) => requirement.ready);
}

function filteredMissingCount(requirements, loopwireOwnedOnly) {
  return filterVerifiedRequirements(requirements, loopwireOwnedOnly)
    .reduce((count, requirement) => count + requirement.missingPorts.length, 0);
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

function formatTsv(payload, includeVerification) {
  const rows = [
    [
      "kind",
      "endpointId",
      "endpointLabel",
      "source",
      "deviceName",
      "channelCount",
      "suggestedPorts",
      ...(includeVerification ? ["ready", "matchedPorts", "missingPorts"] : [])
    ],
    ...payload.requirements.map((requirement) => [
      requirement.kind,
      requirement.endpointId,
      requirement.endpointLabel,
      requirement.source,
      requirement.deviceName,
      String(requirement.channelCount),
      requirement.suggestedPorts.join(","),
      ...(includeVerification
        ? [
            requirement.ready ? "yes" : "no",
            requirement.matchedPorts.join(","),
            requirement.missingPorts.join(",")
          ]
        : [])
    ])
  ];

  return `${rows.map((row) => row.map(formatTsvCell).join("\t")).join("\n")}\n`;
}

function formatTsvCell(value) {
  return String(value).replace(/[\t\r\n]+/g, " ");
}

function firstLine(output) {
  return output.split(/\r?\n/).map((line) => line.trim()).find(Boolean) ?? "unknown error";
}

main().catch((error) => {
  if (error?.code === "ERR_MODULE_NOT_FOUND") {
    console.error("Loopwire packages are not built. Run: pnpm --filter @loopwire/core build && pnpm --filter @loopwire/audio-host build");
    process.exit(1);
  }

  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
