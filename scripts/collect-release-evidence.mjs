#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const outputDir = readOption("--output-dir");
const profile = readOption("--profile") ?? "full";
const releaseTag = readOption("--release-tag") ?? process.env.LOOPWIRE_RELEASE_TAG ?? "v0.1.0";
const releaseRepo = readOption("--repo") ?? process.env.LOOPWIRE_GITHUB_REPO ?? "sandwichfarm/loopwire";
const releasePublicKey =
  readOption("--public-key") ?? process.env.LOOPWIRE_RELEASE_PUBLIC_KEY ?? "packaging/release-signing-public.pem";
const wantsHelp = args.includes("-h") || args.includes("--help");
const listCommands = args.includes("--list-commands");
const requirePublishedRelease = args.includes("--require-published-release");
const summarizeReleaseReadinessLog = readOption("--summarize-release-readiness-log");

if (wantsHelp) {
  usage();
  process.exit(0);
}

if (summarizeReleaseReadinessLog) {
  const output = readFileSync(summarizeReleaseReadinessLog, "utf8");
  const findings = summarizeCommandFindings("release-readiness-publish-preflight", output);
  console.log(JSON.stringify({ findings, blockers: findings.filter((finding) => finding.severity === "blocker") }, null, 2));
  process.exit(0);
}

if (!["quick", "full"].includes(profile)) {
  fail(`unsupported --profile: ${profile}`);
}

if (listCommands) {
  const commands = evidenceCommands(profile).map(({ name, command, log, required = true }) => ({
    name,
    command,
    log,
    required
  }));
  console.log(JSON.stringify(commands, null, 2));
  process.exit(0);
}

if (!outputDir) {
  usage();
  process.exit(2);
}

mkdirSync(outputDir, { recursive: true });

const metadata = {
  generatedAt: new Date().toISOString(),
  profile,
  git: {
    head: readCommand("git rev-parse HEAD"),
    branch: readCommand("git branch --show-current"),
    origin: readCommand("git remote get-url origin"),
    statusShort: readCommand("git status --short")
  },
  tools: {
    node: readCommand("node --version"),
    pnpm: readCommand("pnpm --version"),
    cargo: readCommand("cargo --version", true),
    gh: readCommand("gh --version | head -1", true)
  }
};

const commands = evidenceCommands(profile);
const results = commands.map((command) => runEvidenceCommand(command));
const releaseFindings = results.flatMap((result) => result.findings ?? []);
const manifest = {
  ...metadata,
  release: {
    repo: releaseRepo,
    tag: releaseTag,
    publicKey: releasePublicKey,
    findings: releaseFindings,
    blockers: releaseFindings.filter((finding) => finding.severity === "blocker")
  },
  ok: results.every((result) => !result.required || result.exitCode === 0),
  commands: results
};

writeFileSync(join(outputDir, "release-evidence.json"), `${JSON.stringify(manifest, null, 2)}\n`);

if (!manifest.ok) {
  fail(`evidence collection failed; see ${join(outputDir, "release-evidence.json")}`);
}

console.log(`Release evidence written to ${outputDir}`);

function readOption(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function usage() {
  console.log(`Collect Loopwire release evidence.

Usage:
  collect-release-evidence.mjs --output-dir DIR [--profile quick|full] [--release-tag vX.Y.Z]
  collect-release-evidence.mjs --list-commands [--profile quick|full] [--require-published-release]

Profiles:
  quick  Script/docs/VM metadata checks plus backend detection and Rust compile.
  full   Full workspace check plus backend detection, Rust compile, workflow parse, and GSD state.

Release options:
  --release-tag TAG  Release tag to validate. Defaults to LOOPWIRE_RELEASE_TAG or v0.1.0.
  --repo OWNER/REPO  GitHub repository for optional full preflight. Defaults to sandwichfarm/loopwire.
  --public-key FILE  Release signing public key path. Defaults to packaging/release-signing-public.pem.
  --require-published-release
                     Include published-release installer smoke as required evidence.
                     Full profile includes it as optional evidence by default.
  --list-commands    Print the command plan as JSON without running commands or writing files.
  --summarize-release-readiness-log FILE
                     Parse a release-readiness log into JSON findings without running commands.

Writes:
  release-evidence.json
  *.log command output files
`);
}

function fail(message) {
  console.error(`collect-release-evidence: ${message}`);
  process.exit(1);
}

function evidenceCommands(selectedProfile) {
  const releaseCandidateReadiness = {
    name: "release-readiness-candidate",
    command: shellCommand([
      "bash",
      "scripts/verify-release-readiness.sh",
      "--repo",
      releaseRepo,
      "--tag",
      releaseTag,
      "--public-key",
      releasePublicKey,
      "--skip-gh",
      "--skip-tag",
      "--skip-public-key",
      "--allow-candidate-notes"
    ]),
    log: "release-readiness-candidate.log"
  };
  const publishedReleaseSmoke = {
    name: "published-release-smoke",
    command: shellCommand([
      "bash",
      "scripts/verify-published-release.sh",
      "--repo",
      releaseRepo,
      "--tag",
      releaseTag,
      "--public-key",
      releasePublicKey
    ]),
    log: "published-release-smoke.log",
    required: requirePublishedRelease
  };

  const common = [
    releaseCandidateReadiness,
    {
      name: "audio-detect",
      command: "pnpm --filter @loopwire/audio-host build && node scripts/detect-audio-backends.mjs --pretty",
      log: "audio-detect.json"
    },
    {
      name: "tauri-cargo-check",
      command: "cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml",
      log: "tauri-cargo-check.log"
    }
  ];

  if (selectedProfile === "quick") {
    const commands = [
      { name: "verify-scripts", command: "pnpm verify:scripts", log: "verify-scripts.log" },
      { name: "verify-vm", command: "pnpm verify:vm", log: "verify-vm.log" },
      { name: "verify-docs", command: "pnpm verify:docs", log: "verify-docs.log" },
      ...common
    ];

    return requirePublishedRelease ? [...commands, publishedReleaseSmoke] : commands;
  }

  return [
    { name: "workspace-check", command: "pnpm check", log: "workspace-check.log" },
    ...common,
    {
      name: "release-readiness-publish-preflight",
      command: shellCommand([
        "bash",
        "scripts/verify-release-readiness.sh",
        "--repo",
        releaseRepo,
        "--tag",
        releaseTag,
        "--public-key",
        releasePublicKey
      ]),
      log: "release-readiness-publish-preflight.log",
      required: false
    },
    publishedReleaseSmoke,
    {
      name: "workflow-yaml-parse",
      command: "ruby -e 'require \"yaml\"; Dir[\".github/workflows/*.yml\"].sort.each { |path| YAML.load_file(path); puts path }'",
      log: "workflow-yaml-parse.log"
    },
    { name: "gsd-milestone-state", command: "gsd-sdk query init.milestone-op", log: "gsd-milestone-state.json" },
    { name: "gsd-roadmap-analyze", command: "gsd-sdk query roadmap.analyze", log: "gsd-roadmap-analyze.json" }
  ];
}

function runEvidenceCommand({ name, command, log, required = true }) {
  const startedAt = new Date().toISOString();
  const result = spawnSync("bash", ["-lc", command], {
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  writeFileSync(join(outputDir, log), output);
  const findings = summarizeCommandFindings(name, output);

  return {
    name,
    command,
    log,
    required,
    startedAt,
    finishedAt: new Date().toISOString(),
    exitCode: result.status ?? 1,
    signal: result.signal,
    bytes: Buffer.byteLength(output),
    findings
  };
}

function summarizeCommandFindings(name, output) {
  if (!["release-readiness-candidate", "release-readiness-publish-preflight"].includes(name)) {
    return [];
  }

  return output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .flatMap((line) => {
      const blocker = line.match(/^(missing|invalid):\s*(.+)$/i);
      if (blocker) {
        return [
          {
            source: name,
            severity: "blocker",
            kind: blocker[1].toLowerCase(),
            message: blocker[2]
          }
        ];
      }

      const warning = line.match(/^(allowed|skipped):\s*(.+)$/i);
      if (warning) {
        return [
          {
            source: name,
            severity: "info",
            kind: warning[1].toLowerCase(),
            message: warning[2]
          }
        ];
      }

      return [];
    });
}

function shellCommand(parts) {
  return parts.map(shellQuote).join(" ");
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
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
