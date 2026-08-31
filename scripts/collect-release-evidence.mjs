#!/usr/bin/env node
import { existsSync, lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const evidenceCommandEnv = { ...process.env };
for (const name of [
  "LOOPWIRE_RELEASE_TAG",
  "LOOPWIRE_RELEASE_VERSION",
  "LOOPWIRE_RELEASE_COMMIT",
  "LOOPWIRE_RELEASE_NOTES_FILE"
]) {
  delete evidenceCommandEnv[name];
}
const outputDir = readOption("--output-dir");
const profile = readOption("--profile") ?? "full";
const releaseTag = readOption("--release-tag") ?? process.env.LOOPWIRE_RELEASE_TAG ?? "v0.1.0";
const releaseRepo = readOption("--repo") ?? process.env.LOOPWIRE_GITHUB_REPO ?? "sandwichfarm/loopwire";
const releasePublicKey =
  readOption("--public-key") ?? process.env.LOOPWIRE_RELEASE_PUBLIC_KEY ?? "packaging/release-signing-public.pem";
const docsLiveBaseUrl = readOption("--docs-base-url") ?? process.env.LOOPWIRE_DOCS_BASE_URL ?? "";
const docsLiveHostname = readOption("--docs-hostname") ?? process.env.BUNNY_PULL_ZONE_HOSTNAME ?? "";
const docsLiveRemotePrefix = readOption("--docs-remote-prefix") ?? process.env.BUNNY_REMOTE_PREFIX ?? "";
const vmTargetInput = readOptions("--vm-target");
const configuredVmTargets = splitList(process.env.LOOPWIRE_VM_TARGETS ?? process.env.LOOPWIRE_VM_TARGET);
const vmEvidenceDirPattern = readOption("--vm-evidence-dir") ?? process.env.LOOPWIRE_VM_EVIDENCE_DIR ?? ".vm/evidence/{target}";
const vmLaunchImageRoot = readOption("--vm-launch-image-root") ?? process.env.LOOPWIRE_VM_IMAGE_ROOT ?? ".vm/images";
const vmLaunchStartPort = readOption("--vm-launch-start-port") ?? process.env.LOOPWIRE_VM_LAUNCH_START_PORT ?? "2222";
const dspConfiguration =
  readOption("--dsp-configuration") ??
  process.env.LOOPWIRE_DSP_CONFIGURATION ??
  "scripts/fixtures/dsp-provider-configuration.json";
const dspFrameCount = readOption("--dsp-frame-count") ?? process.env.LOOPWIRE_DSP_FRAME_COUNT ?? "16";
const jackConfiguration =
  readOption("--jack-configuration") ??
  process.env.LOOPWIRE_JACK_CONFIGURATION ??
  "scripts/fixtures/jack-provider-configuration.json";
const wantsHelp = args.includes("-h") || args.includes("--help");
const listCommands = args.includes("--list-commands");
const requirePublishedRelease = args.includes("--require-published-release");
const requireVmEvidence = args.includes("--require-vm-evidence");
const requireLiveDocs = args.includes("--require-live-docs");
const requireNixRelease = args.includes("--require-nix-release");
const requireDspProviderPlan = args.includes("--require-dsp-provider-plan");
const requireJackProviderPlan = args.includes("--require-jack-provider-plan");
const summarizeReleaseReadinessLog = readOption("--summarize-release-readiness-log");

if (wantsHelp) {
  usage();
  process.exit(0);
}

if (summarizeReleaseReadinessLog) {
  validateLocalPath(summarizeReleaseReadinessLog, "release-readiness log", "file", true);
  const output = readFileSync(summarizeReleaseReadinessLog, "utf8");
  const findings = summarizeCommandFindings("release-readiness-publish-preflight", output);
  console.log(JSON.stringify({ findings, blockers: findings.filter((finding) => finding.severity === "blocker") }, null, 2));
  process.exit(0);
}

if (!["quick", "full"].includes(profile)) {
  fail(`unsupported --profile: ${profile}`);
}

validateReleaseTag(releaseTag);
validateReleaseRepo(releaseRepo);
validateSingleLine(vmLaunchImageRoot, "VM launch image root");
validateTcpPort(vmLaunchStartPort, "VM launch start port");
validateRelativePath(dspConfiguration, "DSP provider configuration");
validatePositiveInteger(dspFrameCount, "DSP provider frame count");
validateRelativePath(jackConfiguration, "JACK provider configuration");

if (requireLiveDocs && !docsLiveBaseUrl && !docsLiveHostname) {
  fail("--require-live-docs needs --docs-base-url or --docs-hostname");
}

const vmTargets = expandVmTargets(vmTargetInput.length > 0 ? vmTargetInput : configuredVmTargets);
const vmEvidenceTargets = vmTargets.map((target) => ({
  target,
  evidenceDir: resolveVmEvidenceDir(target)
}));

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

validateLocalPath(outputDir, "output directory", "dir", false);
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
    docsLive: {
      baseUrl: docsLiveBaseUrl,
      hostname: docsLiveHostname,
      remotePrefix: docsLiveRemotePrefix,
      required: requireLiveDocs
    },
    vmEvidence: {
      targets: vmEvidenceTargets,
      required: requireVmEvidence
    },
    nixReleasePackage: {
      required: requireNixRelease
    },
    vmLaunchPlan: {
      imageRoot: vmLaunchImageRoot,
      startPort: vmLaunchStartPort
    },
    dspProviderPlan: {
      configuration: dspConfiguration,
      frameCount: dspFrameCount,
      required: isDspProviderPlanRequired(profile)
    },
    jackProviderPlan: {
      configuration: jackConfiguration,
      required: isJackProviderPlanRequired(profile)
    },
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
  collect-release-evidence.mjs --list-commands [--profile quick|full] [release evidence options]

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
  --docs-base-url URL
                     Deployed docs URL for live docs smoke. Defaults to LOOPWIRE_DOCS_BASE_URL.
  --docs-hostname HOST
                     Bunny pull-zone hostname for live docs smoke. Defaults to BUNNY_PULL_ZONE_HOSTNAME.
  --docs-remote-prefix PATH
                     Optional docs path prefix. Defaults to BUNNY_REMOTE_PREFIX.
  --require-live-docs
                     Include deployed homepage plus /install.sh smoke as required evidence.
                     Full profile includes it as optional evidence when a docs URL/hostname is configured.
  --require-nix-release
                     Include Nix package build proof from the published release assets as required evidence.
                     Full profile includes it as optional evidence by default.
  --vm-target TARGET VM target id for verified VM bundle evidence. Repeatable.
                     Use "all" to expand every target from vm/targets.tsv.
                     Defaults to LOOPWIRE_VM_TARGET or arch-hyprland-pipewire.
  --vm-evidence-dir DIR
                     VM evidence bundle to verify. Use {target} for multiple targets.
                     Defaults to LOOPWIRE_VM_EVIDENCE_DIR or .vm/evidence/{target}.
  --vm-launch-image-root DIR
                     Image-root placeholder for matrix launch planning.
                     Defaults to LOOPWIRE_VM_IMAGE_ROOT or .vm/images.
  --vm-launch-start-port PORT
                     First SSH port for matrix launch planning. Defaults to 2222.
  --require-vm-evidence
                     Include verified VM evidence as required evidence.
                     Full profile includes it as optional evidence by default.
  --dsp-configuration FILE
                     Configuration used for read-only DSP provider plan evidence.
                     Defaults to scripts/fixtures/dsp-provider-configuration.json.
  --dsp-frame-count N
                     Source frames requested in DSP provider plan evidence. Defaults to 16.
  --require-dsp-provider-plan
                     Include read-only DSP provider plan evidence in quick profile.
                     Full profile includes it as required evidence by default.
  --jack-configuration FILE
                     Configuration used for read-only JACK provider plan evidence.
                     Defaults to scripts/fixtures/jack-provider-configuration.json.
  --require-jack-provider-plan
                     Include read-only JACK provider plan evidence in quick profile.
                     Full profile includes it as required evidence by default.
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

function validateReleaseTag(tag) {
  const tagPattern = /^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$/;

  if (typeof tag !== "string" || !tagPattern.test(tag)) {
    fail(`release tag must be v-prefixed semver without path separators: ${tag ?? "<missing>"}`);
  }
}

function validateReleaseRepo(repo) {
  const repoPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

  if (typeof repo !== "string" || !repoPattern.test(repo)) {
    fail(`repository must use OWNER/REPO without URLs, spaces, or extra path segments: ${repo ?? "<missing>"}`);
  }
}

function validateSingleLine(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    fail(`${label} must be non-empty`);
  }

  if (value.includes("\0") || /[\r\n]/.test(value)) {
    fail(`${label} must be a single safe value`);
  }
}

function validateTcpPort(value, label) {
  if (!/^[0-9]+$/.test(String(value))) {
    fail(`${label} must be a number from 1 to 65535`);
  }

  const parsed = Number(value);
  if (parsed < 1 || parsed > 65535) {
    fail(`${label} must be a number from 1 to 65535`);
  }
}

function validatePositiveInteger(value, label) {
  if (!/^[1-9][0-9]*$/.test(String(value))) {
    fail(`${label} must be a positive integer`);
  }
}

function validateRelativePath(value, label) {
  validateSingleLine(value, label);

  if (value.startsWith("/") || value.split(/[\\/]+/).includes("..")) {
    fail(`${label} must be a relative path without parent traversal`);
  }
}

function validateLocalPath(value, label, expectedType, requireExisting) {
  validateSingleLine(value, label);

  const normalized = value.replace(/^[.][\\/]/, "");
  if (
    normalized.length === 0 ||
    normalized === "/" ||
    normalized === "~" ||
    normalized.startsWith("~/") ||
    normalized.includes("://") ||
    /[*?[\]]/.test(normalized)
  ) {
    fail(`${label} must not be root, home-expanded, URL-like, or contain glob metacharacters`);
  }

  if (normalized.split(/[\\/]+/).some((part) => part === "." || part === "..")) {
    fail(`${label} must not contain . or .. path segments`);
  }

  if (existsSync(value)) {
    const stat = lstatSync(value);
    if (stat.isSymbolicLink()) {
      fail(`${label} must not be a symlink`);
    }
    if (expectedType === "file" && !stat.isFile()) {
      fail(`${label} must be a file when it exists`);
    }
    if (expectedType === "dir" && !stat.isDirectory()) {
      fail(`${label} must be a directory when it exists`);
    }
    return;
  }

  if (requireExisting) {
    fail(`${label} must be a ${expectedType}`);
  }
}

function expandVmTargets(inputTargets) {
  const requestedTargets = inputTargets.length > 0 ? inputTargets.flatMap(splitList) : ["arch-hyprland-pipewire"];
  const knownTargets = readKnownVmTargets();
  const expandedTargets = requestedTargets.flatMap((target) => (target === "all" ? knownTargets : [target]));
  const uniqueTargets = [...new Set(expandedTargets)];

  for (const target of uniqueTargets) {
    if (!knownTargets.includes(target)) {
      fail(`unknown VM target: ${target}`);
    }
  }

  if (uniqueTargets.length === 0) {
    fail("at least one VM target is required");
  }

  return uniqueTargets;
}

function readKnownVmTargets() {
  return readFileSync("vm/targets.tsv", "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"))
    .map((line) => line.split(/\t/)[0]);
}

function resolveVmEvidenceDir(target) {
  if (vmEvidenceDirPattern.includes("{target}")) {
    return vmEvidenceDirPattern.replaceAll("{target}", target);
  }

  if (vmTargets.length > 1) {
    fail("--vm-evidence-dir must include {target} when multiple VM targets are selected");
  }

  return vmEvidenceDirPattern;
}

function vmEvidenceCommandFor({ target, evidenceDir }) {
  const command = [
    "bash",
    "scripts/verify-vm-evidence.sh",
    "--target",
    target,
    "--evidence-dir",
    evidenceDir
  ];

  if (requirePublishedRelease) {
    command.push("--require-published-release", "--release-tag", releaseTag, "--require-github-release-source");
  }

  return command;
}

function vmEvidenceName(target) {
  return vmEvidenceTargets.length === 1 ? "vm-evidence" : `vm-evidence:${target}`;
}

function vmEvidenceLog(target) {
  return vmEvidenceTargets.length === 1 ? "vm-evidence.log" : `vm-evidence-${target}.log`;
}

function docsLiveCommand() {
  const command = [
    "bash",
    "scripts/verify-docs-live.sh",
    "--expected-installer",
    "apps/docs/docs/public/install.sh"
  ];

  if (docsLiveBaseUrl) {
    command.push("--base-url", docsLiveBaseUrl);
  } else {
    command.push("--hostname", docsLiveHostname);
    if (docsLiveRemotePrefix) {
      command.push("--remote-prefix", docsLiveRemotePrefix);
    }
  }

  return {
    name: "docs-live-smoke",
    command: shellCommand(command),
    log: "docs-live-smoke.log",
    required: requireLiveDocs
  };
}

function isDspProviderPlanRequired(selectedProfile) {
  return selectedProfile === "full" || requireDspProviderPlan;
}

function isJackProviderPlanRequired(selectedProfile) {
  return selectedProfile === "full" || requireJackProviderPlan;
}

function dspProviderPlanCommand(selectedProfile) {
  return {
    name: "dsp-provider-plan",
    command: shellCommand([
      "bash",
      "scripts/collect-dsp-provider-plan.sh",
      "--configuration",
      dspConfiguration,
      "--frame-count",
      dspFrameCount,
    ]),
    log: "dsp-provider-plan.tsv",
    required: isDspProviderPlanRequired(selectedProfile)
  };
}

function jackProviderPlanCommand(selectedProfile) {
  return {
    name: "jack-provider-plan",
    command: shellCommand([
      "node",
      "scripts/describe-jack-ports.mjs",
      "--configuration",
      jackConfiguration,
      "--loopwire-owned-only",
      "--pretty",
    ]),
    log: "jack-provider-plan.json",
    required: isJackProviderPlanRequired(selectedProfile)
  };
}

function evidenceCommands(selectedProfile) {
  const offlineReleaseReadiness = {
    name: "release-readiness-offline",
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
      "--skip-clean-git"
    ]),
    log: "release-readiness-offline.log"
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
  const nixReleasePackage = {
    name: "nix-release-package",
    command: shellCommand([
      "bash",
      "scripts/verify-nix-release-package.sh",
      "--repo",
      releaseRepo,
      "--tag",
      releaseTag,
      "--public-key",
      releasePublicKey
    ]),
    log: "nix-release-package.log",
    required: requireNixRelease
  };
  const vmEvidence = vmEvidenceTargets.map((target) => ({
    name: vmEvidenceName(target.target),
    command: shellCommand(vmEvidenceCommandFor(target)),
    log: vmEvidenceLog(target.target),
    required: requireVmEvidence
  }));
  const docsLiveSmoke = docsLiveBaseUrl || docsLiveHostname || requireLiveDocs ? docsLiveCommand() : null;
  const vmLaunchPlanCommand = [
    "bash",
    "scripts/vm-matrix.sh",
    "render-launch-plan",
    "--all",
    "--image-root",
    vmLaunchImageRoot,
    "--start-port",
    vmLaunchStartPort
  ];

  if (requirePublishedRelease) {
    vmLaunchPlanCommand.push(
      "--require-published-release",
      "--release-tag",
      releaseTag,
      "--published-release-repo",
      releaseRepo,
      "--release-public-key",
      releasePublicKey,
      "--require-github-release-source"
    );
  }

  const common = [
    offlineReleaseReadiness,
    {
      name: "vm-launch-plan",
      command: shellCommand(vmLaunchPlanCommand),
      log: "vm-launch-plan.tsv"
    },
    {
      name: "audio-detect",
      command: "pnpm --filter @loopwire/audio-host build && node scripts/detect-audio-backends.mjs --pretty",
      log: "audio-detect.json"
    },
    {
      name: "tauri-verify",
      command: "pnpm verify:tauri",
      log: "tauri-verify.log"
    }
  ];

  if (selectedProfile === "quick") {
    const commands = [
      { name: "verify-scripts", command: "pnpm verify:scripts", log: "verify-scripts.log" },
      { name: "verify-vm", command: "pnpm verify:vm", log: "verify-vm.log" },
      { name: "verify-docs", command: "pnpm verify:docs", log: "verify-docs.log" },
      ...common
    ];
    const requiredEvidence = [
      ...(requirePublishedRelease ? [publishedReleaseSmoke] : []),
      ...(requireLiveDocs ? [docsLiveSmoke] : []),
      ...(requireNixRelease ? [nixReleasePackage] : []),
      ...(requireVmEvidence ? vmEvidence : []),
      ...(requireDspProviderPlan ? [dspProviderPlanCommand(selectedProfile)] : []),
      ...(requireJackProviderPlan ? [jackProviderPlanCommand(selectedProfile)] : [])
    ];

    return [...commands, ...requiredEvidence];
  }

  return [
    { name: "workspace-check", command: "pnpm check", log: "workspace-check.log" },
    ...common,
    dspProviderPlanCommand(selectedProfile),
    jackProviderPlanCommand(selectedProfile),
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
    nixReleasePackage,
    ...(docsLiveSmoke ? [docsLiveSmoke] : []),
    ...vmEvidence,
    {
      name: "workflow-yaml-parse",
      command: "ruby -e 'require \"yaml\"; Dir[\".github/workflows/*.yml\"].sort.each { |path| YAML.load_file(path); puts path }'",
      log: "workflow-yaml-parse.log"
    },
    { name: "gsd-milestone-state", command: "gsd-sdk query init.milestone-op", log: "gsd-milestone-state.json" },
    { name: "gsd-roadmap-analyze", command: "gsd-sdk query roadmap.analyze", log: "gsd-roadmap-analyze.json" }
  ];
}

function readOptions(name) {
  const values = [];

  for (let index = 0; index < args.length; index += 1) {
    if (args[index] !== name) {
      continue;
    }

    const value = args[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`${name} requires a value`);
    }
    values.push(value);
  }

  return values;
}

function splitList(value) {
  if (!value) {
    return [];
  }

  return String(value)
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function runEvidenceCommand({ name, command, log, required = true }) {
  const startedAt = new Date().toISOString();
  const result = spawnSync("bash", ["-lc", command], {
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
    env: evidenceCommandEnv
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
