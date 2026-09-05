#!/usr/bin/env node
import { createPrivateKey, createPublicKey } from "node:crypto";
import { lstatSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const GITHUB_VALUE_LIMIT = 48 * 1024;
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const defaultPublicKeyPath = join(repoRoot, "packaging", "release-signing-public.pem");

const variableSpecs = [
  {
    name: "BUNNY_STORAGE_ZONE",
    required: true,
    source:
      "Bunny dashboard -> Storage -> select the Loopwire zone. Copy the zone name shown at the top exactly.",
    validate: validateStorageZone
  },
  {
    name: "BUNNY_STORAGE_ENDPOINT",
    required: true,
    defaultValue: "https://storage.bunnycdn.com",
    source:
      "Bunny dashboard -> Storage -> select the zone -> FTP & API Access. Use the API hostname with https://. Press Enter for Bunny's global endpoint.",
    validate: validateStorageEndpoint
  },
  {
    name: "BUNNY_PULL_ZONE_ID",
    required: true,
    source:
      "Bunny dashboard -> CDN -> Pull Zones -> select the Loopwire zone. Copy its numeric Pull Zone ID, not the Storage Zone ID.",
    validate: validatePullZoneId
  },
  {
    name: "BUNNY_PULL_ZONE_HOSTNAME",
    requiredForFinal: true,
    source:
      "Bunny dashboard -> CDN -> Pull Zones -> select the Loopwire zone -> Hostnames. Copy only the hostname, without https:// or a path. In deploy scope, skip to leave any existing configuration unchanged.",
    validate: validateHostname
  },
  {
    name: "BUNNY_REMOTE_PREFIX",
    source:
      "Choose this yourself only when Loopwire should deploy below a storage subdirectory. Skip to leave any existing configuration unchanged; an unset value deploys at the storage-zone root.",
    validate: validateRemotePrefix
  }
];

const secretSpecs = [
  {
    name: "BUNNY_ACCESS_KEY",
    required: true,
    source:
      "Bunny dashboard -> Storage -> select the Loopwire zone -> FTP & API Access -> Password. This is the storage-zone password, not the account API key.",
    validate: validateSecretLine
  },
  {
    name: "BUNNY_API_KEY",
    required: true,
    source:
      "Bunny account API key: https://dash.bunny.net/account/api-key. This authorizes CDN cache purges; it is not the storage-zone password.",
    validate: validateSingleLine
  }
];

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }
  if (options.printRequired) {
    printRequired(options.scope);
    return;
  }

  const runner = new GhRunner(options.repo);
  const repo = options.repo ?? (options.dryRun ? null : runner.detectRepository());
  if (!repo) {
    throw new Error("--repo OWNER/REPO is required in dry-run mode or outside a Git checkout");
  }
  validateRepository(repo);
  runner.repo = repo;

  if (options.check) {
    runner.preflight();
    checkConfiguration(runner, options.scope);
    return;
  }

  const reader = new PromptReader(process.stdin, process.stderr);
  try {
    const plan = await collectPlan(reader, options);
    validatePlan(plan, options.scope);

    if (options.dryRun) {
      printPlan(repo, plan, true);
      process.stdout.write(`Dry run complete; GitHub was not contacted for ${repo}.\n`);
      return;
    }

    runner.preflight();
    printPlan(repo, plan, false);
    if (!options.yes) {
      process.stderr.write("\nType APPLY to write these names to GitHub. Values will not be displayed: ");
      const confirmation = await reader.readLine({ hidden: false });
      if (confirmation !== "APPLY") {
        throw new Error("confirmation did not match APPLY; no GitHub values were changed");
      }
    }

    applyPlan(runner, plan);
    process.stdout.write(`GitHub Actions variables and secrets configured for ${repo}.\n`);
  } finally {
    reader.close();
  }
}

function parseArgs(args) {
  const options = {
    repo: null,
    scope: "final",
    publicKeyFile: defaultPublicKeyPath,
    dryRun: false,
    check: false,
    yes: false,
    help: false,
    printRequired: false
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--":
        break;
      case "--repo":
        options.repo = requireArg(args, ++index, arg);
        break;
      case "--scope":
        options.scope = requireArg(args, ++index, arg);
        break;
      case "--public-key-file":
        options.publicKeyFile = requireArg(args, ++index, arg);
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--check":
        options.check = true;
        break;
      case "--yes":
        options.yes = true;
        break;
      case "--print-required":
        options.printRequired = true;
        break;
      case "-h":
      case "--help":
        options.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!new Set(["deploy", "final"]).has(options.scope)) {
    throw new Error("--scope must be deploy or final");
  }
  if (options.check && options.dryRun) {
    throw new Error("--check and --dry-run are mutually exclusive");
  }
  if (options.check && options.yes) {
    throw new Error("--check and --yes are mutually exclusive");
  }
  return options;
}

function requireArg(args, index, flag) {
  const value = args[index];
  if (value === undefined || value.startsWith("--")) {
    throw new Error(`missing value for ${flag}`);
  }
  return value;
}

async function collectPlan(reader, options) {
  const variables = [];
  const secrets = [];

  process.stderr.write(
    `\nLoopwire GitHub Actions setup (${options.scope} scope)\n` +
      "Public configuration is stored as Actions variables. Credentials and signing material are stored as Actions secrets.\n"
  );

  for (const spec of variableSpecs) {
    const required = spec.required || (options.scope === "final" && spec.requiredForFinal);
    const value = await promptValue(reader, spec, { required, sensitive: false });
    if (value !== null) variables.push({ name: spec.name, value });
  }

  for (const spec of secretSpecs) {
    const value = await promptValue(reader, spec, { required: spec.required, sensitive: true });
    secrets.push({ name: spec.name, value: Buffer.from(value, "utf8") });
  }

  if (options.scope === "final") {
    const key = await promptReleaseKey(reader, options.publicKeyFile);
    secrets.push({ name: "LOOPWIRE_RELEASE_PRIVATE_KEY", value: key });
  }

  return { variables, secrets };
}

async function promptValue(reader, spec, { required, sensitive }) {
  process.stderr.write(`\n${spec.name} [GitHub Actions ${sensitive ? "secret" : "variable"}]\n`);
  process.stderr.write(`Where to find it: ${spec.source}\n`);
  if (spec.defaultValue !== undefined) {
    process.stderr.write(`Press Enter to use exactly: ${spec.defaultValue}\n`);
  } else if (!required) {
    process.stderr.write("Press Enter to skip this optional value.\n");
  }

  while (true) {
    process.stderr.write(sensitive ? "Value (hidden): " : "Value: ");
    let value = await reader.readLine({ hidden: sensitive });
    if (value === "" && spec.defaultValue !== undefined) value = spec.defaultValue;
    if (value === "" && !required) return null;
    if (value === "" && required) {
      process.stderr.write(`${spec.name} is required for this scope.\n`);
      continue;
    }
    spec.validate(value, spec.name);
    assertGitHubSize(Buffer.from(value, "utf8"), spec.name);
    return value;
  }
}

async function promptReleaseKey(reader, publicKeyOption) {
  process.stderr.write("\nLOOPWIRE_RELEASE_PRIVATE_KEY [GitHub Actions secret]\n");
  process.stderr.write(
    "Where to find it: generate a dedicated signing pair with `pnpm release:prepare-key`. Enter the local private PEM file path; the file bytes are sent unchanged and the path is never sent to GitHub.\n"
  );
  process.stderr.write("Private key file path: ");
  const privatePath = resolveInputPath(await reader.readLine({ hidden: false }));

  process.stderr.write("\nRelease public key [local validation only; not uploaded]\n");
  process.stderr.write(
    "Where to find it: use the public PEM produced by `pnpm release:prepare-key`. It must match the private key.\n"
  );
  process.stderr.write(`Press Enter to use: ${publicKeyOption}\nPublic key file path: `);
  const publicAnswer = await reader.readLine({ hidden: false });
  const publicPath = resolveInputPath(publicAnswer === "" ? publicKeyOption : publicAnswer);

  const privateBytes = readSafeFile(privatePath, "release private key");
  const publicBytes = readSafeFile(publicPath, "release public key");
  assertGitHubSize(privateBytes, "LOOPWIRE_RELEASE_PRIVATE_KEY");
  validateKeyPair(privateBytes, publicBytes);
  return privateBytes;
}

function validatePlan(plan, scope) {
  const variableNames = new Set(plan.variables.map((item) => item.name));
  const secretNames = new Set(plan.secrets.map((item) => item.name));
  for (const name of requiredVariableNames(scope)) {
    if (!variableNames.has(name)) throw new Error(`missing required GitHub Actions variable: ${name}`);
  }
  for (const name of requiredSecretNames(scope)) {
    if (!secretNames.has(name)) throw new Error(`missing required GitHub Actions secret: ${name}`);
  }
}

function applyPlan(runner, plan) {
  const written = [];
  const ordered = [
    ...plan.variables.map((item) => ({ ...item, type: "variable" })),
    ...plan.secrets.map((item) => ({ ...item, type: "secret" }))
  ];

  for (const item of ordered) {
    try {
      if (item.type === "variable") {
        runner.setVariable(item.name, Buffer.from(item.value, "utf8"));
        const actual = runner.getVariable(item.name);
        if (actual !== item.value) {
          throw new Error("GitHub variable readback did not match the entered UTF-8 value");
        }
      } else {
        runner.setSecret(item.name, item.value);
      }
      written.push(`${item.type}:${item.name}`);
    } catch (error) {
      const completed = written.length === 0 ? "none" : written.join(", ");
      throw new Error(
        `write failed for ${item.type}:${item.name}; successfully written before failure: ${completed}. ` +
          "No values were printed and remaining names were not attempted. " +
          (error instanceof Error ? error.message : String(error))
      );
    }
  }

  const registeredSecrets = runner.listSecretNames();
  for (const item of plan.secrets) {
    if (!registeredSecrets.has(item.name)) {
      throw new Error(`GitHub did not list the newly written secret name: ${item.name}`);
    }
  }
}

function checkConfiguration(runner, scope) {
  let missing = false;
  const variables = runner.listVariableNames();
  for (const name of requiredVariableNames(scope)) {
    if (variables.has(name)) {
      process.stdout.write(`ok: GitHub Actions variable present: ${name}\n`);
    } else {
      process.stderr.write(`missing: GitHub Actions variable: ${name}\n`);
      missing = true;
    }
  }

  const secrets = runner.listSecretNames();
  for (const name of requiredSecretNames(scope)) {
    if (secrets.has(name)) process.stdout.write(`ok: GitHub Actions secret present: ${name}\n`);
    else {
      process.stderr.write(`missing: GitHub Actions secret: ${name}\n`);
      missing = true;
    }
  }

  for (const name of ["BUNNY_PULL_ZONE_HOSTNAME", "BUNNY_REMOTE_PREFIX"]) {
    if (requiredVariableNames(scope).includes(name)) continue;
    if (variables.has(name)) {
      process.stdout.write(`ok: optional GitHub Actions variable present: ${name}\n`);
    } else {
      process.stdout.write(`optional: GitHub Actions variable not set: ${name}\n`);
    }
  }

  if (missing) throw new Error(`GitHub Actions ${scope} configuration is incomplete`);
  process.stdout.write(`ok: GitHub Actions ${scope} configuration is present\n`);
}

function requiredVariableNames(scope) {
  const names = ["BUNNY_STORAGE_ZONE", "BUNNY_STORAGE_ENDPOINT", "BUNNY_PULL_ZONE_ID"];
  if (scope === "final") names.push("BUNNY_PULL_ZONE_HOSTNAME");
  return names;
}

function requiredSecretNames(scope) {
  const names = ["BUNNY_ACCESS_KEY", "BUNNY_API_KEY"];
  if (scope === "final") names.push("LOOPWIRE_RELEASE_PRIVATE_KEY");
  return names;
}

function printPlan(repo, plan, dryRun) {
  process.stdout.write(`\n${dryRun ? "Would configure" : "Ready to configure"} ${repo}:\n`);
  for (const item of plan.variables) process.stdout.write(`  variable: ${item.name}\n`);
  for (const item of plan.secrets) process.stdout.write(`  secret: ${item.name}\n`);
}

class GhRunner {
  constructor(repo) {
    this.repo = repo;
    const testMode = process.env.LOOPWIRE_SETUP_TEST_MODE === "1";
    this.bin = testMode && process.env.LOOPWIRE_GH_BIN ? process.env.LOOPWIRE_GH_BIN : "gh";
    this.prefixArgs = testMode && process.env.LOOPWIRE_GH_SCRIPT ? [process.env.LOOPWIRE_GH_SCRIPT] : [];
  }

  detectRepository() {
    const result = this.run(["repo", "view", "--json", "nameWithOwner"], "detect repository");
    const value = parseJson(result.stdout, "repository detection");
    if (typeof value.nameWithOwner !== "string") throw new Error("gh repo view did not return nameWithOwner");
    return value.nameWithOwner;
  }

  preflight() {
    this.run(["auth", "status"], "GitHub authentication preflight");
    const result = this.run(
      ["repo", "view", this.repo, "--json", "nameWithOwner"],
      "GitHub repository preflight"
    );
    const value = parseJson(result.stdout, "repository preflight");
    if (value.nameWithOwner?.toLowerCase() !== this.repo.toLowerCase()) {
      throw new Error(`GitHub repository preflight returned a different repository for ${this.repo}`);
    }
    this.run(["variable", "list", "--repo", this.repo, "--json", "name"], "Actions variable preflight");
    this.run(["secret", "list", "--repo", this.repo, "--json", "name"], "Actions secret preflight");
  }

  setVariable(name, bytes) {
    this.run(["variable", "set", name, "--repo", this.repo], `set Actions variable ${name}`, bytes);
  }

  setSecret(name, bytes) {
    this.run(["secret", "set", name, "--repo", this.repo], `set Actions secret ${name}`, bytes);
  }

  getVariable(name) {
    const result = this.run(
      ["variable", "get", name, "--repo", this.repo, "--json", "name,value"],
      `read back Actions variable ${name}`
    );
    const value = parseJson(result.stdout, `Actions variable ${name}`);
    if (value.name !== name || typeof value.value !== "string") {
      throw new Error(`GitHub returned malformed readback for variable ${name}`);
    }
    return value.value;
  }

  listVariableNames() {
    const result = this.run(
      ["variable", "list", "--repo", this.repo, "--json", "name"],
      "list Actions variable names"
    );
    const value = parseJson(result.stdout, "Actions variable names");
    if (!Array.isArray(value)) throw new Error("GitHub returned malformed variable-name list");
    return new Set(value.map((item) => item.name).filter((name) => typeof name === "string"));
  }

  listSecretNames() {
    const result = this.run(
      ["secret", "list", "--repo", this.repo, "--json", "name"],
      "list Actions secret names"
    );
    const value = parseJson(result.stdout, "Actions secret names");
    if (!Array.isArray(value)) throw new Error("GitHub returned malformed secret-name list");
    return new Set(value.map((item) => item.name).filter((name) => typeof name === "string"));
  }

  run(args, label, input) {
    const result = spawnSync(this.bin, [...this.prefixArgs, ...args], {
      input,
      encoding: "utf8",
      windowsHide: true,
      maxBuffer: 1024 * 1024,
      env: process.env
    });
    if (result.error) {
      throw new Error(`${label} could not start gh (${result.error.code || result.error.name})`);
    }
    if (result.status !== 0) {
      throw new Error(`${label} failed with gh exit code ${result.status}`);
    }
    return result;
  }
}

class PromptReader {
  constructor(input, output) {
    this.input = input;
    this.output = output;
    this.tty = Boolean(input.isTTY && typeof input.setRawMode === "function");
    this.closed = false;
    this.queue = [];
    this.current = "";
    this.pending = null;
    this.lastWasCarriageReturn = false;

    if (this.tty) {
      this.wasRaw = input.isRaw;
      input.setEncoding("utf8");
      input.setRawMode(true);
      input.resume();
      this.onData = (chunk) => this.consume(chunk);
      input.on("data", this.onData);
    } else {
      const content = readFileSync(0, "utf8");
      this.queue = splitInputLines(content);
    }
  }

  readLine({ hidden }) {
    if (this.closed) return Promise.reject(new Error("prompt input is closed"));
    if (this.queue.length > 0) return Promise.resolve(this.queue.shift());
    if (!this.tty) return Promise.reject(new Error("prompt input ended before all answers were provided"));
    if (this.pending) return Promise.reject(new Error("concurrent prompt reads are not supported"));
    return new Promise((resolveLine, rejectLine) => {
      this.pending = { resolve: resolveLine, reject: rejectLine, hidden };
    });
  }

  consume(chunk) {
    for (const character of [...chunk]) {
      if (character === "\u0003") {
        const pending = this.pending;
        this.pending = null;
        pending?.reject(new Error("input cancelled; no further GitHub values were changed"));
        this.close();
        return;
      }
      if (character === "\n" && this.lastWasCarriageReturn) {
        this.lastWasCarriageReturn = false;
        continue;
      }
      if (character === "\r" || character === "\n") {
        this.lastWasCarriageReturn = character === "\r";
        const line = this.current;
        this.current = "";
        this.output.write("\n");
        if (this.pending) {
          const pending = this.pending;
          this.pending = null;
          pending.resolve(line);
        } else {
          this.queue.push(line);
        }
        continue;
      }
      this.lastWasCarriageReturn = false;
      if (character === "\u007f" || character === "\b") {
        if (this.current.length > 0) {
          this.current = [...this.current].slice(0, -1).join("");
          if (this.pending && !this.pending.hidden) this.output.write("\b \b");
        }
        continue;
      }
      this.current += character;
      const codePoint = character.codePointAt(0);
      const isTerminalControl = codePoint < 0x20 || codePoint === 0x7f;
      if (this.pending && !this.pending.hidden && !isTerminalControl) this.output.write(character);
    }
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    if (this.tty) {
      this.input.off("data", this.onData);
      this.input.setRawMode(Boolean(this.wasRaw));
      this.input.pause();
    }
  }
}

function splitInputLines(content) {
  if (content === "") return [];
  const lines = content.split("\n").map((line) => (line.endsWith("\r") ? line.slice(0, -1) : line));
  if (content.endsWith("\n")) lines.pop();
  return lines;
}

function validateStorageZone(value, name) {
  validateSingleLine(value, name);
  rejectSurroundingWhitespace(value, name);
  if (value.includes("/") || value.includes("\\")) throw new Error(`${name} must be a zone name, not a path`);
}

function validateStorageEndpoint(value, name) {
  validateSingleLine(value, name);
  rejectSurroundingWhitespace(value, name);
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${name} must be an http:// or https:// origin`);
  }
  if (!new Set(["http:", "https:"]).has(url.protocol) || url.username || url.password) {
    throw new Error(`${name} must be an http:// or https:// origin without credentials`);
  }
  if ((url.pathname && url.pathname !== "/") || url.search || url.hash) {
    throw new Error(`${name} must not include a path, query, or fragment`);
  }
}

function validateHostname(value, name) {
  validateSingleLine(value, name);
  rejectSurroundingWhitespace(value, name);
  if (!/^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(value)) {
    throw new Error(`${name} must be a hostname without a scheme, port, or path`);
  }
}

function validatePullZoneId(value, name) {
  if (!/^[0-9]+$/.test(value) || BigInt(value) < 1n || BigInt(value) > 9223372036854775807n) {
    throw new Error(`${name} must be a positive integer no greater than 9223372036854775807`);
  }
}

function validateRemotePrefix(value, name) {
  validateSingleLine(value, name);
  rejectSurroundingWhitespace(value, name);
  if (value.startsWith("/") || value.endsWith("/") || value.includes("\\")) {
    throw new Error(`${name} must be a relative path without leading or trailing slashes`);
  }
  if (!/^[A-Za-z0-9._~/-]+$/.test(value)) {
    throw new Error(`${name} contains characters that are unsafe in Bunny object paths`);
  }
  if (value.split("/").some((segment) => segment === "." || segment === ".." || segment === "")) {
    throw new Error(`${name} must not contain empty, . or .. path segments`);
  }
}

function validateSecretLine(value, name) {
  if (value === "") throw new Error(`${name} must not be empty`);
  if (value.includes("\0") || value.includes("\r") || value.includes("\n")) {
    throw new Error(`${name} must be a single-line value without NUL bytes`);
  }
}

function validateSingleLine(value, name) {
  if (value === "") throw new Error(`${name} must not be empty`);
  if (/[\u0000-\u001f\u007f]/u.test(value)) {
    throw new Error(`${name} must not contain control characters`);
  }
}

function rejectSurroundingWhitespace(value, name) {
  if (value !== value.trim()) {
    throw new Error(`${name} has leading or trailing whitespace; refusing to modify it silently`);
  }
}

function assertGitHubSize(bytes, name) {
  if (bytes.length === 0) throw new Error(`${name} must not be empty`);
  if (bytes.length > GITHUB_VALUE_LIMIT) {
    throw new Error(`${name} exceeds GitHub's 48 KB value limit; input was not truncated`);
  }
}

function resolveInputPath(value) {
  if (value === "") throw new Error("release key file path must not be empty");
  let expanded = value;
  if (value === "~") expanded = homedir();
  else if (value.startsWith("~/") || value.startsWith("~\\")) expanded = join(homedir(), value.slice(2));
  return isAbsolute(expanded) ? expanded : resolve(process.cwd(), expanded);
}

function readSafeFile(path, label) {
  let stats;
  try {
    stats = lstatSync(path);
  } catch {
    throw new Error(`${label} file does not exist`);
  }
  if (stats.isSymbolicLink()) throw new Error(`${label} file must not be a symbolic link`);
  if (!stats.isFile()) throw new Error(`${label} path must be a regular file`);
  const bytes = readFileSync(path);
  if (bytes.length === 0) throw new Error(`${label} file must not be empty`);
  return bytes;
}

function validateKeyPair(privateBytes, publicBytes) {
  let privateKey;
  let publicKey;
  try {
    privateKey = createPrivateKey(privateBytes);
  } catch {
    throw new Error("release private key does not parse as a PEM private key");
  }
  try {
    publicKey = createPublicKey(publicBytes);
  } catch {
    throw new Error("release public key does not parse as a PEM public key");
  }
  const derived = createPublicKey(privateKey).export({ type: "spki", format: "der" });
  const expected = publicKey.export({ type: "spki", format: "der" });
  if (!derived.equals(expected)) throw new Error("release private key does not match the supplied public key");
}

function validateRepository(repo) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) {
    throw new Error("--repo must use the OWNER/REPO form");
  }
}

function parseJson(text, label) {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${label} returned invalid JSON from gh`);
  }
}

function printRequired(scope) {
  process.stdout.write(`Required ${scope} GitHub Actions configuration:\n`);
  for (const name of requiredVariableNames(scope)) process.stdout.write(`  variable: ${name}\n`);
  for (const name of requiredSecretNames(scope)) process.stdout.write(`  secret: ${name}\n`);
  process.stdout.write("Optional variables: BUNNY_PULL_ZONE_HOSTNAME (deploy only), BUNNY_REMOTE_PREFIX\n");
}

function printHelp() {
  process.stdout.write(`Configure Loopwire GitHub Actions variables and secrets through guarded prompts.\nRuns through Node.js and GitHub CLI on Windows, macOS, and Linux.\n\nUsage:\n  node scripts/setup-github-actions.mjs --repo OWNER/REPO [--scope deploy|final]\n  node scripts/setup-github-actions.mjs --repo OWNER/REPO --dry-run [--scope deploy|final]\n  node scripts/setup-github-actions.mjs --repo OWNER/REPO --check [--scope deploy|final]\n  node scripts/setup-github-actions.mjs --print-required [--scope deploy|final]\n\nOptions:\n  --repo OWNER/REPO        Target repository; detected with gh outside dry-run when omitted\n  --scope deploy|final     Deploy variables/secrets only, or final release proof (default: final)\n  --public-key-file FILE   Public PEM used to validate the prompted private key\n  --dry-run                Prompt and validate locally without invoking gh\n  --check                  Check required GitHub variable/secret names without reading secrets\n  --yes                    Skip the final APPLY confirmation after all preflight checks\n  --print-required         Print required names and GitHub storage types\n\nSecurity:\n  Values are never accepted as CLI flags or environment variables. Variables and secrets are sent to gh through stdin.\n  Secret values are never printed. The release private key is read from a non-symlink regular file and passed byte-for-byte.\n`);
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`setup-github-actions: ${message}\n`);
  process.exitCode = 1;
});
