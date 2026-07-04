#!/usr/bin/env node
import { existsSync, lstatSync, readFileSync, realpathSync, statSync } from "node:fs";
import { isAbsolute, join, relative } from "node:path";

const args = process.argv.slice(2);
const evidenceDir = readOption("--evidence-dir");
const expectedReleaseTag = readOption("--release-tag");
const expectedRepo = readOption("--repo");
const expectedPublicKey = readOption("--public-key");
const expectedGitHead = readOption("--git-head");
const requirePublishedRelease = args.includes("--require-published-release");
const requireLiveDocs = args.includes("--require-live-docs");
const requireNixRelease = args.includes("--require-nix-release");
const requireVmEvidence = args.includes("--require-vm-evidence");
const requireAllVmTargets = args.includes("--require-all-vm-targets");
const requireVmLaunchPlan = args.includes("--require-vm-launch-plan");
const requireDspProviderPlan = args.includes("--require-dsp-provider-plan");
const requireNoReleaseBlockers = args.includes("--require-no-release-blockers");
const requireCleanGit = args.includes("--require-clean-git");
const projectRoot = process.cwd();

if (args.includes("-h") || args.includes("--help")) {
  usage();
  process.exit(0);
}

if (!evidenceDir) {
  usage();
  process.exit(2);
}

const manifestPath = join(evidenceDir, "release-evidence.json");
const evidenceRoot = realpathSync(evidenceDir);
const manifest = readJson(manifestPath);

if (manifest.ok !== true) {
  fail("release evidence manifest is not ok");
}

if (expectedReleaseTag) {
  validateReleaseTag(expectedReleaseTag, "expected release tag");
}

if (expectedRepo) {
  validateReleaseRepo(expectedRepo, "expected repository");
}

if (expectedPublicKey) {
  validatePublicKeyPath(expectedPublicKey, "expected public key");
}

if (expectedGitHead) {
  validateGitHead(expectedGitHead, "expected git head");
}

validateReleaseTag(manifest.release?.tag, "release evidence tag");
validateReleaseRepo(manifest.release?.repo, "release evidence repository");
validatePublicKeyPath(manifest.release?.publicKey, "release evidence public key");

if (expectedReleaseTag && manifest.release?.tag !== expectedReleaseTag) {
  fail(`release evidence tag mismatch: expected ${expectedReleaseTag}, got ${manifest.release?.tag ?? "<missing>"}`);
}

if (expectedRepo && manifest.release?.repo !== expectedRepo) {
  fail(`release evidence repo mismatch: expected ${expectedRepo}, got ${manifest.release?.repo ?? "<missing>"}`);
}

if (expectedPublicKey && manifest.release?.publicKey !== expectedPublicKey) {
  fail(`release evidence public key mismatch: expected ${expectedPublicKey}, got ${manifest.release?.publicKey ?? "<missing>"}`);
}

if (!Array.isArray(manifest.commands) || manifest.commands.length === 0) {
  fail("release evidence manifest has no command results");
}

validateGitMetadata(manifest.git);
if (expectedGitHead && manifest.git.head.toLowerCase() !== expectedGitHead.toLowerCase()) {
  fail(`release evidence git head mismatch: expected ${expectedGitHead}, got ${manifest.git.head}`);
}

for (const command of manifest.commands) {
  validateCommand(command);
}

if (requireNoReleaseBlockers && (manifest.release?.blockers?.length ?? 0) > 0) {
  fail("release evidence contains release blockers");
}

if (requirePublishedRelease) {
  const command = findCommand("published-release-smoke");
  if (!command) {
    fail("missing command result: published-release-smoke");
  }
  if (command.required !== true || command.exitCode !== 0) {
    fail("published-release-smoke must be required and successful");
  }
  validatePublishedReleaseCommand(command);
}

if (requireLiveDocs) {
  const command = findCommand("docs-live-smoke");
  if (!command) {
    fail("missing command result: docs-live-smoke");
  }
  if (command.required !== true || command.exitCode !== 0) {
    fail("docs-live-smoke must be required and successful");
  }
  validateLiveDocsCommand(command);
}

if (requireNixRelease) {
  const command = findCommand("nix-release-package");
  if (!command) {
    fail("missing command result: nix-release-package");
  }
  if (command.required !== true || command.exitCode !== 0) {
    fail("nix-release-package must be required and successful");
  }
  validateNixReleaseCommand(command);
}

if (requireVmEvidence) {
  validateRequiredVmEvidence();
}

if (requireVmLaunchPlan) {
  validateRequiredVmLaunchPlan();
}

if (requireDspProviderPlan) {
  validateRequiredDspProviderPlan();
}

console.log(`Release evidence verified: ${evidenceDir}`);

function usage() {
  console.log(`Verify Loopwire release evidence.

Usage:
  verify-release-evidence.mjs --evidence-dir DIR [options]

Options:
  --release-tag TAG
                     Require release.tag in the manifest to match TAG.
  --repo OWNER/REPO
                     Require release.repo in the manifest to match OWNER/REPO.
  --public-key FILE
                     Require release.publicKey in the manifest to match FILE.
  --git-head SHA
                     Require git.head in the manifest to match SHA.
  --require-published-release
                     Require successful published-release-smoke evidence.
  --require-live-docs
                     Require successful deployed docs homepage and installer smoke evidence.
  --require-nix-release
                     Require successful Nix package build proof from published release assets.
  --require-vm-evidence
                     Require successful VM evidence commands for manifest targets.
  --require-all-vm-targets
                     Require VM evidence targets to match every target in vm/targets.tsv.
  --require-vm-launch-plan
                     Require matrix-wide dry-run VM launch-plan evidence.
  --require-dsp-provider-plan
                     Require read-only command-backed DSP provider plan evidence.
  --require-no-release-blockers
                     Fail if release.findings contains blocker entries.
  --require-clean-git
                     Require the collected git status to be clean.
`);
}

function readOption(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function fail(message) {
  console.error(`verify-release-evidence: ${message}`);
  process.exit(1);
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`failed to read JSON: ${path}: ${error.message}`);
  }
}

function validateReleaseTag(tag, label) {
  const tagPattern = /^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$/;

  if (typeof tag !== "string" || !tagPattern.test(tag)) {
    fail(`${label} must be v-prefixed semver without path separators: ${tag ?? "<missing>"}`);
  }
}

function validateReleaseRepo(repo, label) {
  const repoPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

  if (typeof repo !== "string" || !repoPattern.test(repo)) {
    fail(`${label} must use OWNER/REPO without URLs, spaces, or extra path segments: ${repo ?? "<missing>"}`);
  }
}

function validatePublicKeyPath(path, label) {
  if (typeof path !== "string" || path.trim().length === 0) {
    fail(`${label} must be a non-empty file path`);
  }

  if (path.includes("\0")) {
    fail(`${label} contains a null byte`);
  }

  if (/[\r\n]/.test(path)) {
    fail(`${label} must be a single line`);
  }
}

function validateGitHead(head, label) {
  if (typeof head !== "string" || !/^[0-9a-f]{40}$/i.test(head)) {
    fail(`${label} must be a 40-character commit SHA`);
  }
}

function validateGitMetadata(git) {
  if (!git || typeof git !== "object" || Array.isArray(git)) {
    fail("release evidence manifest is missing git metadata");
  }

  validateGitHead(git.head, "release evidence git head");

  validateGitTextField(git.branch, "branch", { allowEmpty: true });
  validateGitTextField(git.origin, "origin");
  validateGitTextField(git.statusShort, "statusShort", { allowEmpty: true, allowMultiline: true });

  if (requireCleanGit && git.statusShort.trim().length > 0) {
    fail("release evidence git status is not clean");
  }
}

function validateGitTextField(value, name, options = {}) {
  const { allowEmpty = false, allowMultiline = false } = options;

  if (typeof value !== "string") {
    fail(`release evidence git ${name} must be a string`);
  }

  if (!allowEmpty && value.trim().length === 0) {
    fail(`release evidence git ${name} must not be empty`);
  }

  if (value.includes("\0")) {
    fail(`release evidence git ${name} contains a null byte`);
  }

  if (!allowMultiline && /[\r\n]/.test(value)) {
    fail(`release evidence git ${name} must be a single line`);
  }

  if (value.startsWith("unavailable:")) {
    fail(`release evidence git ${name} is unavailable`);
  }
}

function validateCommand(command) {
  if (!command || typeof command.name !== "string" || command.name.length === 0) {
    fail("command result is missing a name");
  }

  if (typeof command.log !== "string" || command.log.length === 0) {
    fail(`command ${command.name} is missing a log path`);
  }

  const logPath = resolveEvidenceFile(command.log, `command ${command.name} log`);
  if (!existsSync(logPath)) {
    fail(`missing command log: ${command.log}`);
  }

  if (lstatSync(logPath).isSymbolicLink()) {
    fail(`command ${command.name} log must not be a symlink: ${command.log}`);
  }

  if (!statSync(logPath).isFile()) {
    fail(`command ${command.name} log is not a file: ${command.log}`);
  }

  if (readFileSync(logPath, "utf8").trim().length === 0) {
    fail(`empty command log: ${command.log}`);
  }

  if (command.required !== false && command.exitCode !== 0) {
    fail(`required command failed: ${command.name}`);
  }
}

function resolveEvidenceFile(path, label) {
  if (typeof path !== "string" || path.length === 0) {
    fail(`${label} path is missing`);
  }

  if (path.includes("\0")) {
    fail(`${label} path contains a null byte`);
  }

  if (isAbsolute(path)) {
    fail(`${label} path must be relative: ${path}`);
  }

  if (path.split(/[\\/]+/).includes("..")) {
    fail(`${label} path must not contain parent traversal: ${path}`);
  }

  const candidate = join(evidenceRoot, path);
  const realCandidate = existsSync(candidate) ? realpathSync(candidate) : candidate;
  const relativePath = relative(evidenceRoot, realCandidate);

  if (relativePath === "" || relativePath.startsWith("..") || isAbsolute(relativePath)) {
    fail(`${label} path escapes evidence directory: ${path}`);
  }

  return candidate;
}

function findCommand(name) {
  return manifest.commands.find((command) => command.name === name);
}

function validateRequiredVmEvidence() {
  const vmTargets = manifest.release?.vmEvidence?.targets;
  if (!Array.isArray(vmTargets) || vmTargets.length === 0) {
    fail("release evidence manifest has no VM evidence targets");
  }

  const targetIds = validateVmEvidenceTargets(vmTargets);
  assertKnownVmTargets(targetIds);

  if (requireAllVmTargets) {
    assertAllVmTargets(targetIds);
  }

  for (const target of vmTargets) {
    const command = findVmEvidenceCommand(target.target, vmTargets.length);
    if (!command) {
      fail(`missing VM evidence command result for target: ${target.target}`);
    }
    if (command.required !== true || command.exitCode !== 0) {
      fail(`VM evidence command must be required and successful: ${command.name}`);
    }
    validateVmEvidenceCommand(command, target);
  }
}

function validateRequiredVmLaunchPlan() {
  const command = findCommand("vm-launch-plan");
  if (!command) {
    fail("missing command result: vm-launch-plan");
  }

  if (command.required !== true || command.exitCode !== 0) {
    fail("vm-launch-plan must be required and successful");
  }

  const tokens = validateScriptInvocation(command, "scripts/vm-matrix.sh", "vm-launch-plan");
  if (tokens[2] !== "render-launch-plan") {
    fail("vm-launch-plan command must invoke render-launch-plan");
  }
  if (!tokens.includes("--all")) {
    fail("vm-launch-plan command must include --all");
  }

  const binding = manifest.release?.vmLaunchPlan;
  if (!binding || typeof binding !== "object" || Array.isArray(binding)) {
    fail("release evidence is missing vmLaunchPlan binding metadata");
  }

  requireOptionValue(tokens, "--image-root", binding.imageRoot, "vm-launch-plan");
  requireOptionValue(tokens, "--start-port", binding.startPort, "vm-launch-plan");
  validateVmLaunchPlanLog(command.log, binding);
}

function validateRequiredDspProviderPlan() {
  const command = findCommand("dsp-provider-plan");
  if (!command) {
    fail("missing command result: dsp-provider-plan");
  }

  if (command.required !== true || command.exitCode !== 0) {
    fail("dsp-provider-plan must be required and successful");
  }

  const tokens = validateScriptInvocation(command, "scripts/collect-dsp-provider-plan.sh", "dsp-provider-plan");
  if (tokens.includes("--execute")) {
    fail("dsp-provider-plan command must not include --execute");
  }

  const binding = manifest.release?.dspProviderPlan;
  if (!binding || typeof binding !== "object" || Array.isArray(binding)) {
    fail("release evidence is missing dspProviderPlan binding metadata");
  }
  if (binding.required !== true) {
    fail("dsp-provider-plan command must be marked required in release evidence metadata");
  }

  validateDspConfigurationPath(binding.configuration);
  validatePositiveIntegerCell(binding.frameCount, "DSP provider frame count");
  requireOptionValue(tokens, "--configuration", binding.configuration, "dsp-provider-plan");
  requireOptionValue(tokens, "--frame-count", binding.frameCount, "dsp-provider-plan");
  validateDspProviderPlanLog(command.log, binding);
}

function validateDspConfigurationPath(value) {
  if (typeof value !== "string" || value.length === 0) {
    fail("DSP provider configuration path is missing");
  }

  if (value.includes("\0") || /[\r\n]/.test(value)) {
    fail("DSP provider configuration path must be a single safe value");
  }

  if (isAbsolute(value) || value.split(/[\\/]+/).includes("..")) {
    fail("DSP provider configuration path must be relative and must not contain parent traversal");
  }
}

function validateDspProviderPlanLog(log, binding) {
  const logPath = resolveEvidenceFile(log, "dsp-provider-plan log");
  const expectedRows = expectedDspProviderRows(binding);
  const lines = readFileSync(logPath, "utf8")
    .trim()
    .split(/\r?\n/)
    .filter((line) => line.length > 0);

  const header = lines.shift();
  if (header !== "operation\ttarget\tlabel\tchannels\tframes") {
    fail("dsp-provider-plan log has an unexpected header");
  }

  const operations = new Set();
  const seenRows = new Set();
  for (const line of lines) {
    const cells = line.split("\t");
    if (cells.length !== 5) {
      fail("dsp-provider-plan row must have 5 TSV columns");
    }

    const [operation, target, label, channels, frames] = cells;
    const rowKey = `${operation}\t${target}`;
    if (!["read-source", "write-output", "verify-output"].includes(operation)) {
      fail(`dsp-provider-plan row has unsupported operation: ${operation}`);
    }
    if (!target || !label) {
      fail("dsp-provider-plan row must include target and label");
    }

    validatePositiveIntegerCell(channels, `dsp-provider-plan channels for ${target}`);
    if (frames !== binding.frameCount) {
      fail(`dsp-provider-plan frames mismatch for ${target}: expected ${binding.frameCount}, got ${frames}`);
    }

    const expected = expectedRows.get(rowKey);
    if (!expected) {
      fail(`dsp-provider-plan row is not expected for configuration ${binding.configuration}: ${operation} ${target}`);
    }
    if (label !== expected.label) {
      fail(`dsp-provider-plan label mismatch for ${operation} ${target}: expected ${expected.label}, got ${label}`);
    }
    if (channels !== expected.channels) {
      fail(`dsp-provider-plan channels mismatch for ${operation} ${target}: expected ${expected.channels}, got ${channels}`);
    }
    if (seenRows.has(rowKey)) {
      fail(`dsp-provider-plan row is duplicated: ${operation} ${target}`);
    }

    seenRows.add(rowKey);
    operations.add(operation);
  }

  for (const [rowKey] of expectedRows) {
    if (!seenRows.has(rowKey)) {
      fail(`dsp-provider-plan log is missing expected row: ${rowKey.replace("\t", " ")}`);
    }
  }

  for (const operation of ["read-source", "write-output", "verify-output"]) {
    if (!operations.has(operation)) {
      fail(`dsp-provider-plan log is missing operation: ${operation}`);
    }
  }
}

function expectedDspProviderRows(binding) {
  const configuration = readDspProviderConfiguration(binding.configuration);
  const inputs = new Map(configuration.inputs.map((input) => [input.id, input]));
  const outputs = new Map(configuration.outputs.map((output) => [output.id, output]));
  const sourceRows = new Map();
  const expectedRows = new Map();

  for (const route of configuration.routes) {
    const input = inputs.get(route.from);
    const output = outputs.get(route.to);
    if (!input || !output) {
      fail(`DSP provider configuration has an invalid route: ${route.id ?? `${route.from}->${route.to}`}`);
    }

    const channels = String(Math.min(input.channels, output.channels));
    const existing = sourceRows.get(input.id);
    sourceRows.set(input.id, {
      label: input.label,
      channels: String(Math.max(Number(existing?.channels ?? 0), Number(channels)))
    });
  }

  for (const [sourceId, row] of [...sourceRows.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    expectedRows.set(`read-source\t${sourceId}`, row);
  }

  for (const output of configuration.outputs) {
    const row = { label: output.label, channels: String(output.channels) };
    expectedRows.set(`write-output\t${output.id}`, row);
    expectedRows.set(`verify-output\t${output.id}`, row);
  }

  return expectedRows;
}

function readDspProviderConfiguration(configurationPath) {
  const value = readJson(join(projectRoot, configurationPath));
  const configuration = value?.kind === "loopwire.configuration" && value?.version === 1
    ? value.configuration
    : value;

  if (!configuration || typeof configuration !== "object" || Array.isArray(configuration)) {
    fail("DSP provider configuration must be an object or configuration export");
  }

  validateDspEndpointArray(configuration.inputs, "inputs");
  validateDspEndpointArray(configuration.outputs, "outputs");
  if (!Array.isArray(configuration.routes)) {
    fail("DSP provider configuration routes must be an array");
  }

  for (const route of configuration.routes) {
    if (!route || typeof route !== "object" || Array.isArray(route)) {
      fail("DSP provider configuration routes must contain objects");
    }
    if (typeof route.from !== "string" || typeof route.to !== "string") {
      fail("DSP provider configuration routes must include from and to ids");
    }
  }

  return configuration;
}

function validateDspEndpointArray(endpoints, label) {
  if (!Array.isArray(endpoints)) {
    fail(`DSP provider configuration ${label} must be an array`);
  }

  for (const endpoint of endpoints) {
    if (!endpoint || typeof endpoint !== "object" || Array.isArray(endpoint)) {
      fail(`DSP provider configuration ${label} must contain endpoint objects`);
    }
    if (typeof endpoint.id !== "string" || endpoint.id.length === 0) {
      fail(`DSP provider configuration ${label} endpoints must include ids`);
    }
    if (typeof endpoint.label !== "string" || endpoint.label.length === 0) {
      fail(`DSP provider configuration ${label} endpoints must include labels`);
    }
    validatePositiveIntegerCell(String(endpoint.channels), `DSP provider configuration ${label} channels for ${endpoint.id}`);
  }
}

function validateVmLaunchPlanLog(log, binding) {
  const logPath = resolveEvidenceFile(log, "vm-launch-plan log");
  const lines = readFileSync(logPath, "utf8")
    .trim()
    .split(/\r?\n/)
    .filter((line) => line.length > 0);

  const header = lines.shift();
  const expectedHeader = "# target\timage\timage_format\tfirmware\tssh_port\tmemory\tcpus\tlaunch_command\tevidence_pull_command";
  if (header !== expectedHeader) {
    fail("vm-launch-plan log has an unexpected header");
  }

  const expectedTargets = readKnownVmTargets();
  const seenTargets = new Set();

  for (const line of lines) {
    const cells = line.split("\t");
    if (cells.length !== 9) {
      fail("vm-launch-plan row must have 9 TSV columns");
    }

    const [target, image, imageFormat, _firmware, sshPort, memory, cpus, launchCommand, evidenceCommand] = cells;
    if (!expectedTargets.includes(target)) {
      fail(`vm-launch-plan contains unknown target: ${target}`);
    }
    if (seenTargets.has(target)) {
      fail(`vm-launch-plan contains duplicate target: ${target}`);
    }

    seenTargets.add(target);
    validateVmLaunchPlanRow({
      target,
      image,
      imageFormat,
      sshPort,
      memory,
      cpus,
      launchCommand,
      evidenceCommand,
      binding
    });
  }

  const missing = expectedTargets.filter((target) => !seenTargets.has(target));
  if (missing.length > 0) {
    fail(`vm-launch-plan is missing targets: ${missing.join(", ")}`);
  }
}

function validateVmLaunchPlanRow({
  target,
  image,
  imageFormat,
  sshPort,
  memory,
  cpus,
  launchCommand,
  evidenceCommand,
  binding
}) {
  if (image !== `${String(binding.imageRoot).replace(/\/$/, "")}/${target}.${imageFormat}`) {
    fail(`vm-launch-plan image path mismatch for ${target}`);
  }

  if (!["qcow2", "raw"].includes(imageFormat)) {
    fail(`vm-launch-plan image format is unsupported for ${target}: ${imageFormat}`);
  }

  validatePortCell(sshPort, `vm-launch-plan SSH port for ${target}`);
  validatePositiveIntegerCell(memory, `vm-launch-plan memory for ${target}`);
  validatePositiveIntegerCell(cpus, `vm-launch-plan CPU count for ${target}`);

  const launchTokens = splitShellWords(launchCommand, `vm-launch-plan launch command for ${target}`);
  if (launchTokens[0] !== "bash" || launchTokens[1] !== "scripts/vm-matrix.sh" || launchTokens[2] !== "launch") {
    fail(`vm-launch-plan launch command for ${target} must invoke bash scripts/vm-matrix.sh launch`);
  }
  requireOptionValue(launchTokens, "--target", target, `vm-launch-plan launch command for ${target}`);
  requireOptionValue(launchTokens, "--image", image, `vm-launch-plan launch command for ${target}`);
  requireOptionValue(launchTokens, "--image-format", imageFormat, `vm-launch-plan launch command for ${target}`);
  requireOptionValue(launchTokens, "--ssh-port", sshPort, `vm-launch-plan launch command for ${target}`);

  const evidenceTokens = splitShellWords(evidenceCommand, `vm-launch-plan evidence command for ${target}`);
  if (
    evidenceTokens[0] !== "bash" ||
    evidenceTokens[1] !== "scripts/collect-vm-evidence-ssh.sh"
  ) {
    fail(`vm-launch-plan evidence command for ${target} must invoke bash scripts/collect-vm-evidence-ssh.sh`);
  }
  requireOptionValue(evidenceTokens, "--target", target, `vm-launch-plan evidence command for ${target}`);
  requireOptionValue(evidenceTokens, "--host", "127.0.0.1", `vm-launch-plan evidence command for ${target}`);
  requireOptionValue(evidenceTokens, "--port", sshPort, `vm-launch-plan evidence command for ${target}`);
  if (!evidenceTokens.includes("--execute")) {
    fail(`vm-launch-plan evidence command for ${target} must include --execute`);
  }
}

function validatePortCell(value, label) {
  if (!/^[0-9]+$/.test(String(value))) {
    fail(`${label} must be a number from 1 to 65535`);
  }

  const parsed = Number(value);
  if (parsed < 1 || parsed > 65535) {
    fail(`${label} must be a number from 1 to 65535`);
  }
}

function validatePositiveIntegerCell(value, label) {
  if (!/^[1-9][0-9]*$/.test(String(value))) {
    fail(`${label} must be a positive integer`);
  }
}

function validateVmEvidenceTargets(vmTargets) {
  const seenTargets = new Set();
  const targetIds = [];

  for (const entry of vmTargets) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      fail("release evidence manifest contains an invalid VM target entry");
    }

    if (typeof entry.target !== "string" || entry.target.length === 0) {
      fail("release evidence manifest contains an invalid VM target");
    }

    if (seenTargets.has(entry.target)) {
      fail(`release evidence manifest contains a duplicate VM target: ${entry.target}`);
    }

    seenTargets.add(entry.target);
    targetIds.push(entry.target);
    validateVmEvidenceDir(entry.evidenceDir, entry.target);
  }

  return targetIds;
}

function validateVmEvidenceDir(evidenceDir, target) {
  if (typeof evidenceDir !== "string" || evidenceDir.length === 0) {
    fail(`VM evidence target ${target} is missing evidenceDir`);
  }

  if (evidenceDir.includes("\0")) {
    fail(`VM evidence target ${target} evidenceDir contains a null byte`);
  }

  if (isAbsolute(evidenceDir)) {
    fail(`VM evidence target ${target} evidenceDir must be relative: ${evidenceDir}`);
  }

  const pathSegments = evidenceDir.split(/[\\/]+/).filter(Boolean);
  if (pathSegments.includes("..")) {
    fail(`VM evidence target ${target} evidenceDir must not contain parent traversal: ${evidenceDir}`);
  }

  if (!pathSegments.includes(target)) {
    fail(`VM evidence target ${target} evidenceDir must include the target id as a path segment`);
  }
}

function validateVmEvidenceCommand(command, target) {
  const tokens = validateScriptInvocation(command, "scripts/verify-vm-evidence.sh", `VM evidence command ${command.name}`);
  requireOptionValue(tokens, "--target", target.target, `VM evidence command ${command.name}`);
  requireOptionValue(tokens, "--evidence-dir", target.evidenceDir, `VM evidence command ${command.name}`);

  if (requirePublishedRelease && !tokens.includes("--require-published-release")) {
    fail(`VM evidence command ${command.name} must require published-release smoke`);
  }
}

function validateLiveDocsCommand(command) {
  const tokens = validateScriptInvocation(command, "scripts/verify-docs-live.sh", "docs-live-smoke");
  const docsLive = manifest.release?.docsLive;

  requireOptionValue(tokens, "--expected-installer", "apps/docs/docs/public/install.sh", "docs-live-smoke");

  if (!docsLive || typeof docsLive !== "object" || Array.isArray(docsLive)) {
    fail("docs-live-smoke command is missing docsLive binding metadata");
  }

  if (docsLive.required !== true) {
    fail("docs-live-smoke command must be marked required in release evidence metadata");
  }

  if (typeof docsLive.baseUrl === "string" && docsLive.baseUrl.length > 0) {
    requireOptionValue(tokens, "--base-url", docsLive.baseUrl, "docs-live-smoke");
    rejectOption(tokens, "--hostname", "docs-live-smoke");
    return;
  }

  if (typeof docsLive.hostname !== "string" || docsLive.hostname.length === 0) {
    fail("docs-live-smoke command is missing docs hostname metadata");
  }

  requireOptionValue(tokens, "--hostname", docsLive.hostname, "docs-live-smoke");
  rejectOption(tokens, "--base-url", "docs-live-smoke");

  if (typeof docsLive.remotePrefix === "string" && docsLive.remotePrefix.length > 0) {
    requireOptionValue(tokens, "--remote-prefix", docsLive.remotePrefix, "docs-live-smoke");
  } else {
    rejectOption(tokens, "--remote-prefix", "docs-live-smoke");
  }
}

function validatePublishedReleaseCommand(command) {
  const tokens = validateScriptInvocation(command, "scripts/verify-published-release.sh", "published-release-smoke");
  const requiredBindings = [
    ["--repo", manifest.release?.repo],
    ["--tag", manifest.release?.tag],
    ["--public-key", manifest.release?.publicKey]
  ];

  for (const [flag, value] of requiredBindings) {
    if (typeof value !== "string" || value.length === 0) {
      fail("published-release-smoke command is missing release binding metadata");
    }

    requireOptionValue(tokens, flag, value, "published-release-smoke");
  }
}

function validateNixReleaseCommand(command) {
  const tokens = validateScriptInvocation(command, "scripts/verify-nix-release-package.sh", "nix-release-package");
  const requiredBindings = [
    ["--repo", manifest.release?.repo],
    ["--tag", manifest.release?.tag],
    ["--public-key", manifest.release?.publicKey]
  ];

  for (const [flag, value] of requiredBindings) {
    if (typeof value !== "string" || value.length === 0) {
      fail("nix-release-package command is missing release binding metadata");
    }

    requireOptionValue(tokens, flag, value, "nix-release-package");
  }

  if (tokens.includes("--release-dir")) {
    fail("nix-release-package command must use published release coordinates, not --release-dir");
  }
  if (tokens.includes("--skip-build-if-missing-nix") || tokens.includes("--render-only")) {
    fail("nix-release-package command must not use skip or render-only modes");
  }
}

function validateScriptInvocation(command, scriptPath, label) {
  if (typeof command.command !== "string" || command.command.length === 0) {
    fail(`${label} command is missing the executed command`);
  }

  const tokens = splitShellWords(command.command, label);

  if (tokens[0] !== "bash" || tokens[1] !== scriptPath) {
    fail(`${label} command must invoke bash ${scriptPath}`);
  }

  return tokens;
}

function requireOptionValue(tokens, flag, expectedValue, label) {
  const index = tokens.indexOf(flag);

  if (index < 0) {
    fail(`${label} command is missing ${flag}`);
  }

  const actualValue = tokens[index + 1];
  if (actualValue !== expectedValue) {
    fail(`${label} command ${flag} mismatch: expected ${expectedValue}, got ${actualValue ?? "<missing>"}`);
  }
}

function rejectOption(tokens, flag, label) {
  if (tokens.includes(flag)) {
    fail(`${label} command must not include ${flag}`);
  }
}

function splitShellWords(command, label) {
  const words = [];
  let current = "";
  let quote = "";
  let escaping = false;
  let tokenStarted = false;

  for (const char of command) {
    if (escaping) {
      current += char;
      tokenStarted = true;
      escaping = false;
      continue;
    }

    if (quote === "'") {
      if (char === "'") {
        quote = "";
      } else {
        current += char;
      }
      tokenStarted = true;
      continue;
    }

    if (quote === "\"") {
      if (char === "\"") {
        quote = "";
      } else if (char === "\\") {
        escaping = true;
      } else {
        current += char;
      }
      tokenStarted = true;
      continue;
    }

    if (char === "\\") {
      escaping = true;
      tokenStarted = true;
    } else if (char === "'" || char === "\"") {
      quote = char;
      tokenStarted = true;
    } else if (/\s/.test(char)) {
      if (tokenStarted) {
        words.push(current);
        current = "";
        tokenStarted = false;
      }
    } else {
      current += char;
      tokenStarted = true;
    }
  }

  if (escaping) {
    fail(`${label} command has a trailing escape`);
  }

  if (quote) {
    fail(`${label} command has an unterminated quote`);
  }

  if (tokenStarted) {
    words.push(current);
  }

  return words;
}

function findVmEvidenceCommand(target, targetCount) {
  if (targetCount === 1) {
    return findCommand("vm-evidence") ?? findCommand(`vm-evidence:${target}`);
  }

  return findCommand(`vm-evidence:${target}`);
}

function assertAllVmTargets(actualTargets) {
  const expectedTargets = readKnownVmTargets();
  const missing = expectedTargets.filter((target) => !actualTargets.includes(target));
  const extra = actualTargets.filter((target) => !expectedTargets.includes(target));

  if (missing.length > 0) {
    fail(`release evidence is missing VM targets: ${missing.join(", ")}`);
  }

  if (extra.length > 0) {
    fail(`release evidence includes unknown VM targets: ${extra.join(", ")}`);
  }
}

function assertKnownVmTargets(actualTargets) {
  const expectedTargets = readKnownVmTargets();
  const unknown = actualTargets.filter((target) => !expectedTargets.includes(target));

  if (unknown.length > 0) {
    fail(`release evidence includes unknown VM targets: ${unknown.join(", ")}`);
  }
}

function readKnownVmTargets() {
  return readFileSync("vm/targets.tsv", "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"))
    .map((line) => line.split(/\t/)[0]);
}
