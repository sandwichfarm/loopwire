#!/usr/bin/env node
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { arch, hostname, platform, release, type, userInfo } from "node:os";

const args = process.argv.slice(2);
const outputDir = readOption("--output-dir");
const profile = readOption("--profile") ?? "quick";

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

mkdirSync(outputDir, { recursive: true });

const redact = createRedactor();
const commands = supportCommands(profile);
const results = commands.map((command) => runSupportCommand(command, redact));
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

Profiles:
  quick  Backend detection, host diagnostics, and autostart status.
  full   Quick profile plus workspace check and Tauri Rust compile.

Writes:
  support-bundle.json
  command-results.tsv
  notes.md
  detect-audio.json
  ct-host-check.log
  autostart-status.log
  optional full-profile command logs
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
      command: "pnpm --filter @loopwire/audio-host build >/dev/null && node scripts/detect-audio-backends.mjs --pretty",
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

  if (selectedProfile === "quick") {
    return quick;
  }

  return [
    ...quick,
    {
      name: "workspace-check",
      command: "pnpm check",
      log: "workspace-check.log"
    },
    {
      name: "tauri-cargo-check",
      command: "cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml",
      log: "tauri-cargo-check.log"
    }
  ];
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
    "- ct-host-check.log: redacted host audio diagnostics.",
    "- autostart-status.log: user-scoped startup status.",
    "- workspace-check.log and tauri-cargo-check.log: present only in the full profile."
  ];

  writeFileSync(join(targetDir, "notes.md"), `${lines.join("\n")}\n`);
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
