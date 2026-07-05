#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { arch, hostname, platform, release, type, userInfo } from "node:os";

const args = process.argv.slice(2);
const configurationFile = readOption("--configuration");
const configurationId = readOption("--configuration-id");
const dspFrameCount = readOption("--dsp-frame-count") ?? "16";
const dspProviderCommand = readOption("--dsp-provider-command");
const includeDspProviderPlan = args.includes("--include-dsp-provider-plan") || Boolean(dspProviderCommand);
const jackPortsFile = readOption("--jack-ports-file");
const outputDir = readOption("--output-dir");
const profile = readOption("--profile") ?? "quick";
const stateFile = readOption("--state-file");

if (args.includes("-h") || args.includes("--help")) {
  usage();
  process.exit(0);
}

if (!outputDir) {
  usage();
  fail("missing --output-dir", 2);
}

if (!["quick", "full"].includes(profile)) {
  fail(`unsupported --profile: ${profile}`, 2);
}

if (!/^[1-9][0-9]*$/.test(dspFrameCount)) {
  fail("--dsp-frame-count must be a positive integer", 2);
}

mkdirSync(outputDir, { recursive: true });

const redact = createRedactor();
const commands = supportCommands(profile);
const results = commands.map((command) => runSupportCommand(command, redact));
const audio = summarizeAudioDetection(outputDir);
const dspProvider = summarizeDspProviderPlan(outputDir);
const jack = summarizeJackReadiness(outputDir);
const manifest = {
  kind: "loopwire.support-bundle",
  version: 1,
  generatedAt: new Date().toISOString(),
  profile,
  redacted: true,
  status: results.every((result) => result.exitCode === 0) ? "passed" : "completed_with_failures",
  system: {
    platform: platform(),
    arch: arch(),
    kernel: redact(`${type()} ${release()}`),
    desktop: redact(process.env.XDG_CURRENT_DESKTOP ?? "unknown"),
    session: redact(process.env.XDG_SESSION_TYPE ?? "unknown"),
    wayland: process.env.WAYLAND_DISPLAY ? "<set>" : "none",
    x11: process.env.DISPLAY ? "<set>" : "none"
  },
  git: {
    head: redact(readCommand("git rev-parse HEAD", true)),
    branch: redact(readCommand("git branch --show-current", true)),
    origin: redact(readCommand("git remote get-url origin", true)),
    statusShort: redact(readCommand("git status --short", true))
  },
  tools: {
    node: redact(readCommand("node --version", true)),
    pnpm: redact(readCommand("pnpm --version", true)),
    cargo: redact(readCommand("cargo --version", true)),
    tauri: redact(readCommand("cargo tauri --version", true))
  },
  audio,
  dspProvider,
  jack,
  commands: results
};

writeFileSync(join(outputDir, "support-bundle.json"), `${JSON.stringify(manifest, null, 2)}\n`);
writeFileSync(join(outputDir, "command-results.tsv"), commandResultsTsv(results));
writeNotes(outputDir, manifest);

console.log(`Support bundle written to ${outputDir}`);

function readOption(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function usage() {
  console.log(`Collect a redacted Loopwire support bundle.

Usage:
  collect-support-bundle.mjs --output-dir DIR [--profile quick|full]
                             [--configuration FILE | --state-file FILE [--configuration-id ID]]
                             [--jack-ports-file FILE]
                             [--include-dsp-provider-plan]
                             [--dsp-provider-command COMMAND]
                             [--dsp-frame-count N]

Profiles:
  quick  Backend detection, host diagnostics, and autostart status.
  full   Quick profile plus workspace check and Tauri shell verification.

Writes:
  support-bundle.json
  command-results.tsv
  notes.md
  detect-audio.json
  ct-host-check.log
  autostart-status.log
  optional dsp-provider-plan.json
  optional full-profile command logs

Optional JACK readiness input:
  --configuration FILE       Loopwire configuration export or raw configuration JSON for JACK readiness.
  --state-file FILE          Persisted Loopwire state for JACK readiness.
  --configuration-id ID      Select a configuration from --state-file.
  --jack-ports-file FILE     Verify against captured jack_lsp output instead of live jack_lsp.

Optional DSP provider input:
  --include-dsp-provider-plan   Include a read-only DSP provider operation plan from the selected configuration.
  --dsp-provider-command COMMAND Probe provider capabilities in read-only mode.
  --dsp-frame-count N           Bounded source frames requested for the plan. Default: 16.
`);
}

function fail(message, code = 1) {
  console.error(`collect-support-bundle: ${message}`);
  process.exit(code);
}

function supportCommands(selectedProfile) {
  const quick = [
    {
      name: "detect-audio",
      command: "pnpm --filter @loopwire/audio-host build >/dev/null 2>&1 && node scripts/detect-audio-backends.mjs --pretty",
      log: "detect-audio.json"
    },
    {
      name: "ct-host-check",
      command: "bash scripts/ct-host-check.sh",
      log: "ct-host-check.log"
    },
    {
      name: "autostart-status",
      command: "bash scripts/manage-autostart.sh status --mode desktop",
      log: "autostart-status.log"
    }
  ];
  const jackCommand = jackReadinessCommand();
  const dspCommand = dspProviderPlanCommand();
  const quickWithOptional = [...quick, jackCommand, dspCommand].filter(Boolean);

  if (selectedProfile === "quick") {
    return quickWithOptional;
  }

  return [
    ...quickWithOptional,
    {
      name: "workspace-check",
      command: "pnpm check",
      log: "workspace-check.log"
    },
    {
      name: "tauri-verify",
      command: "pnpm verify:tauri",
      log: "tauri-verify.log"
    }
  ];
}

function jackReadinessCommand() {
  const selectorArgs = configurationSelectorArgs({
    required: Boolean(jackPortsFile),
    label: "--jack-ports-file"
  });

  if (!selectorArgs) {
    return undefined;
  }

  const portsArgs = jackPortsFile ? ["--ports-file", jackPortsFile] : [];
  const commandArgs = [
    "node",
    "scripts/describe-jack-ports.mjs",
    "--verify",
    "--pretty",
    ...selectorArgs,
    ...portsArgs
  ];

  return {
    name: "jack-readiness",
    command: [
      "pnpm --filter @loopwire/core build >/dev/null 2>&1",
      "pnpm --filter @loopwire/audio-host build >/dev/null 2>&1",
      commandArgs.map(shellQuote).join(" ")
    ].join(" && "),
    log: "jack-port-requirements.json"
  };
}

function dspProviderPlanCommand() {
  if (!includeDspProviderPlan) {
    return undefined;
  }

  const selectorArgs = configurationSelectorArgs({
    required: true,
    label: "--include-dsp-provider-plan"
  });
  const providerArgs = dspProviderCommand
    ? ["--provider-command", dspProviderCommand, "--require-live-capability"]
    : [];
  const commandArgs = [
    "node",
    "scripts/describe-dsp-provider.mjs",
    "--pretty",
    "--frame-count",
    dspFrameCount,
    ...selectorArgs,
    ...providerArgs
  ];

  return {
    name: "dsp-provider-plan",
    command: [
      "pnpm --filter @loopwire/core build >/dev/null 2>&1",
      "pnpm --filter @loopwire/audio-host build >/dev/null 2>&1",
      commandArgs.map(shellQuote).join(" ")
    ].join(" && "),
    log: "dsp-provider-plan.json"
  };
}

function configurationSelectorArgs({ required, label }) {
  const selectorArgs = [];

  if (configurationFile) {
    if (configurationId) {
      fail("--configuration-id can only be used with --state-file", 2);
    }

    selectorArgs.push("--configuration", configurationFile);
  } else if (stateFile) {
    selectorArgs.push("--state-file", stateFile);

    if (configurationId) {
      selectorArgs.push("--configuration-id", configurationId);
    }
  } else if (configurationId) {
    fail("--configuration-id requires --state-file", 2);
  } else if (required) {
    fail(`${label} requires --configuration or --state-file`, 2);
  } else {
    return undefined;
  }

  return selectorArgs;
}

function runSupportCommand({ name, command, log }, redact) {
  const startedAt = new Date().toISOString();
  const result = spawnSync("bash", ["-lc", command], {
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024
  });
  const rawOutput = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  const redactedOutput = redact(rawOutput);
  writeFileSync(join(outputDir, log), redactedOutput);

  return {
    name,
    command,
    log,
    startedAt,
    finishedAt: new Date().toISOString(),
    exitCode: result.status ?? 1,
    signal: result.signal,
    bytes: Buffer.byteLength(redactedOutput)
  };
}

function readCommand(command, optional = false) {
  const result = spawnSync("bash", ["-lc", command], {
    encoding: "utf8",
    maxBuffer: 1024 * 1024
  });

  if (result.status !== 0) {
    return optional ? "" : `unavailable: ${command}`;
  }

  return result.stdout.trim();
}

function commandResultsTsv(results) {
  const rows = ["name\texitCode\tstartedAt\tfinishedAt\tlog"];

  for (const result of results) {
    rows.push([result.name, result.exitCode, result.startedAt, result.finishedAt, result.log].join("\t"));
  }

  return `${rows.join("\n")}\n`;
}

function writeNotes(targetDir, manifest) {
  const lines = [
    "# Loopwire Support Bundle",
    "",
    `- Generated: ${manifest.generatedAt}`,
    `- Profile: ${manifest.profile}`,
    `- Status: ${manifest.status}`,
    "- Redaction: local user, host, home directory, runtime uid paths, process ids, cookies, and email-like values.",
    "",
    "Review this directory before sharing. Do not attach raw audio recordings, secrets, or private configuration files.",
    "",
    "## Files",
    "",
    "- support-bundle.json: manifest, tool versions, git state, command statuses.",
    "- command-results.tsv: command ledger.",
    "- detect-audio.json: backend detection and capability report.",
    "- support-bundle.json audio.backends: summarized backend availability, route-control scope, and known gaps.",
    "- jack-port-requirements.json: present only when a Loopwire configuration/state is provided for JACK readiness.",
    "- dsp-provider-plan.json: present only when DSP provider plan collection is requested.",
    "- ct-host-check.log: redacted host audio diagnostics.",
    "- autostart-status.log: user-scoped startup status.",
    "- workspace-check.log and tauri-verify.log: present only in the full profile."
  ];

  writeFileSync(join(targetDir, "notes.md"), `${lines.join("\n")}\n`);
}

function summarizeDspProviderPlan(targetDir) {
  const dspPath = join(targetDir, "dsp-provider-plan.json");

  try {
    const report = JSON.parse(readFileSync(dspPath, "utf8"));
    if (!Array.isArray(report.operations)) {
      return { status: "invalid", message: "dsp-provider-plan.json did not contain operations." };
    }

    return {
      status: "parsed",
      ok: report.ok === true,
      mode: report.mode ?? "",
      configurationId: report.configurationId ?? "",
      configurationName: report.configurationName ?? "",
      frameCount: Number.isInteger(report.frameCount) ? report.frameCount : 0,
      providerCommand: report.providerCommand ? "<provided>" : "not_provided",
      providerCapability: summarizeDspProviderCapability(report.providerCapability),
      operations: report.operations.map((operation) => ({
        operation: operation.operation ?? "unknown",
        target: operation.target ?? "",
        label: operation.label ?? "",
        channels: Number.isInteger(operation.channels) ? operation.channels : 0,
        frames: Number.isInteger(operation.frames) ? operation.frames : 0
      }))
    };
  } catch (error) {
    if (error?.code === "ENOENT") {
      return { status: "not_requested" };
    }

    return {
      status: "invalid",
      message: error instanceof Error ? error.message : "dsp-provider-plan.json could not be parsed."
    };
  }
}

function summarizeDspProviderCapability(capability) {
  if (!capability || typeof capability !== "object" || Array.isArray(capability)) {
    return { status: "not_requested" };
  }

  return {
    status: "parsed",
    ok: capability.ok === true,
    supportsLiveGraph: capability.supportsLiveGraph === true,
    operations: Array.isArray(capability.operations)
      ? capability.operations.filter((operation) => typeof operation === "string")
      : [],
    message: typeof capability.message === "string" ? capability.message : ""
  };
}

function summarizeAudioDetection(targetDir) {
  const detectAudioPath = join(targetDir, "detect-audio.json");

  try {
    const report = JSON.parse(readFileSync(detectAudioPath, "utf8"));
    if (!Array.isArray(report.reports)) {
      return { status: "invalid", backends: [], message: "detect-audio.json did not contain a reports array." };
    }

    return {
      status: "parsed",
      generatedAt: report.generatedAt ?? "",
      platform: report.platform ?? "",
      backends: report.reports.map((backend) => ({
        kind: backend.kind ?? "unknown",
        displayName: backend.displayName ?? String(backend.kind ?? "unknown"),
        availability: backend.availability ?? "unavailable",
        transport: backend.transport ?? "unknown",
        controlScope: backend.mixing?.controlScope ?? "unknown",
        supportsPerEdgeGain: backend.mixing?.supportsPerEdgeGain === true,
        supportsPerEdgeMute: backend.mixing?.supportsPerEdgeMute === true,
        gaps: Array.isArray(backend.gaps) ? backend.gaps : [],
        diagnostics: Array.isArray(backend.diagnostics)
          ? backend.diagnostics.map((diagnostic) => ({
            level: diagnostic.level ?? "warning",
            code: diagnostic.code ?? "UNKNOWN",
            message: diagnostic.message ?? ""
          }))
          : []
      }))
    };
  } catch (error) {
    return {
      status: "invalid",
      backends: [],
      message: error instanceof Error ? error.message : "detect-audio.json could not be parsed."
    };
  }
}

function summarizeJackReadiness(targetDir) {
  const jackPath = join(targetDir, "jack-port-requirements.json");

  try {
    const report = JSON.parse(readFileSync(jackPath, "utf8"));
    if (!Array.isArray(report.requirements)) {
      return { status: "invalid", message: "jack-port-requirements.json did not contain requirements." };
    }

    return {
      status: "parsed",
      ok: report.ok === true,
      configurationId: report.configurationId ?? "",
      configurationName: report.configurationName ?? "",
      portSource: report.portSource ?? "",
      portCount: Number.isInteger(report.portCount) ? report.portCount : 0,
      missingCount: Number.isInteger(report.missingCount) ? report.missingCount : 0,
      requirements: report.requirements.map((requirement) => ({
        kind: requirement.kind ?? "unknown",
        endpointId: requirement.endpointId ?? "",
        endpointLabel: requirement.endpointLabel ?? "",
        source: requirement.source ?? "unknown",
        deviceName: requirement.deviceName ?? "",
        channelCount: Number.isInteger(requirement.channelCount) ? requirement.channelCount : 0,
        ready: requirement.ready === true,
        matchedPorts: Array.isArray(requirement.matchedPorts) ? requirement.matchedPorts : [],
        missingPorts: Array.isArray(requirement.missingPorts) ? requirement.missingPorts : []
      }))
    };
  } catch (error) {
    if (error?.code === "ENOENT") {
      return { status: "not_requested" };
    }

    return {
      status: "invalid",
      message: error instanceof Error ? error.message : "jack-port-requirements.json could not be parsed."
    };
  }
}

function createRedactor() {
  const replacements = [
    [process.env.HOME, "<home>"],
    [safeUserName(), "<user>"],
    [hostname(), "<host>"]
  ].filter(([value]) => typeof value === "string" && value.length > 1);

  replacements.sort(([left], [right]) => right.length - left.length);

  return (value) => {
    let output = String(value);

    for (const [needle, replacement] of replacements) {
      output = output.replaceAll(needle, replacement);
    }

    return output
      .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "<email>")
      .replace(/\/run\/user\/[0-9]+/g, "/run/user/<uid>")
      .replace(/pid:[0-9]+/g, "pid:<redacted>")
      .replace(/cookie:[0-9]+/g, "cookie:<redacted>")
      .replace(/^Cookie: .*$/gm, "Cookie: <redacted>")
      .replace(/^User Name: .*$/gm, "User Name: <user>")
      .replace(/^Host Name: .*$/gm, "Host Name: <host>");
  };
}

function safeUserName() {
  try {
    return userInfo().username;
  } catch {
    return "";
  }
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}
