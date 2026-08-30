#!/usr/bin/env node

import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { lstat, readFile, readdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";

const schema = "loopwire.release-assets.v1";
const manifestName = "release-assets.json";
const ignoredNames = new Set([manifestName, "SHA256SUMS", "SHA256SUMS.sig"]);

function fail(message) {
  console.error(`release-asset-manifest: ${message}`);
  process.exit(1);
}

function usage() {
  console.log(`Usage:
  release-asset-manifest.mjs write --release-dir DIR --tag vX.Y.Z --git-head COMMIT
  release-asset-manifest.mjs verify --release-dir DIR --tag vX.Y.Z --git-head COMMIT
    [--require-checksum] [--require-evidence]

Writes or verifies ${manifestName}. Unknown, missing, extra, linked, mis-versioned, or misclassified payload assets
fail closed. SHA256SUMS and SHA256SUMS.sig are transport metadata and are not listed as payload artifacts.`);
}

function parseArgs(argv) {
  const command = argv.shift();
  if (command === "--help" || command === "-h") {
    usage();
    process.exit(0);
  }
  if (!["write", "verify"].includes(command)) fail("first argument must be write or verify");
  const options = { command, requireChecksum: false, requireEvidence: false };
  while (argv.length > 0) {
    const argument = argv.shift();
    if (argument === "--require-checksum") options.requireChecksum = true;
    else if (argument === "--require-evidence") options.requireEvidence = true;
    else if (["--release-dir", "--tag", "--git-head"].includes(argument)) {
      const value = argv.shift();
      if (!value || value.startsWith("--")) fail(`missing value for ${argument}`);
      options[argument.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
    } else fail(`unknown argument: ${argument}`);
  }
  if (!options.releaseDir) fail("--release-dir is required");
  if (!/^v[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z][0-9A-Za-z.-]*)?$/.test(options.tag ?? "")) {
    fail("--tag must be a safe v-prefixed semantic version");
  }
  if (!/^[0-9a-f]{40}$/.test(options.gitHead ?? "")) fail("--git-head must be a full lowercase commit hash");
  if (command === "write" && (options.requireChecksum || options.requireEvidence)) {
    fail("write does not accept verification requirement flags");
  }
  return options;
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizeArch(value) {
  if (["amd64", "x86_64"].includes(value)) return "x86_64";
  if (["arm64", "aarch64"].includes(value)) return "aarch64";
  fail(`unsupported artifact architecture: ${value}`);
}

function classify(name, version, tag) {
  let match;
  if ((match = /^loopwire-linux-(x86_64|aarch64)\.tar\.gz$/.exec(name))) {
    return { kind: "portable-archive", target: "linux-generic", architecture: match[1] };
  }
  const appImagePattern = new RegExp(`^Loopwire_${escapeRegex(version)}_(amd64|x86_64|arm64|aarch64)\\.AppImage$`);
  if ((match = appImagePattern.exec(name))) {
    return { kind: "desktop-appimage", target: "linux-generic", architecture: normalizeArch(match[1]) };
  }
  const exact = new Map([
    [`loopwire_${version}-1ubuntu24.04_amd64.deb`, { kind: "native-deb", target: "ubuntu-24.04", architecture: "x86_64" }],
    [`loopwire_${version}-1debian13_amd64.deb`, { kind: "native-deb", target: "debian-13", architecture: "x86_64" }],
    [`loopwire-${version}-1.fc44.x86_64.rpm`, { kind: "native-rpm", target: "fedora-44", architecture: "x86_64" }],
    [`loopwire-${version}-1.x86_64.rpm`, { kind: "native-rpm", target: "opensuse-tumbleweed", architecture: "x86_64" }],
    [`loopwire-release-evidence-${tag}.tar.gz`, { kind: "release-evidence", target: "verification", architecture: "multi" }],
  ]);
  const result = exact.get(name);
  if (!result) fail(`unrecognized or mis-versioned release payload: ${name}`);
  return result;
}

async function sha256(file) {
  const hash = createHash("sha256");
  await new Promise((resolve, reject) => {
    const stream = createReadStream(file);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("error", reject);
    stream.on("end", resolve);
  });
  return hash.digest("hex");
}

async function buildManifest(releaseDir, tag, gitHead, requireEvidence) {
  const version = tag.slice(1);
  const directoryStat = await lstat(releaseDir).catch(() => fail(`release directory does not exist: ${releaseDir}`));
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) fail("release directory must be a real directory");
  const names = (await readdir(releaseDir)).filter((name) => !ignoredNames.has(name)).sort();
  if (names.length === 0) fail("release directory has no payload artifacts");
  const artifacts = [];
  const logicalKeys = new Set();
  for (const name of names) {
    if (path.basename(name) !== name) fail(`release asset is not a basename: ${name}`);
    const file = path.join(releaseDir, name);
    const stat = await lstat(file);
    if (!stat.isFile() || stat.isSymbolicLink()) fail(`release asset must be a regular non-link file: ${name}`);
    const classification = classify(name, version, tag);
    const logicalKey = `${classification.kind}:${classification.target}:${classification.architecture}`;
    if (logicalKeys.has(logicalKey)) fail(`duplicate logical release asset: ${logicalKey}`);
    logicalKeys.add(logicalKey);
    artifacts.push({ name, ...classification, bytes: stat.size, sha256: await sha256(file) });
  }
  const required = [
    "portable-archive:linux-generic:x86_64",
    "portable-archive:linux-generic:aarch64",
    "desktop-appimage:linux-generic:x86_64",
    "desktop-appimage:linux-generic:aarch64",
    "native-deb:ubuntu-24.04:x86_64",
    "native-deb:debian-13:x86_64",
    "native-rpm:fedora-44:x86_64",
    "native-rpm:opensuse-tumbleweed:x86_64",
  ];
  for (const key of required) if (!logicalKeys.has(key)) fail(`missing required release artifact: ${key}`);
  const evidenceKey = "release-evidence:verification:multi";
  if (requireEvidence && !logicalKeys.has(evidenceKey)) fail("release evidence artifact is required");
  return { schema, release: { tag, version, gitHead }, artifacts };
}

function stableJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

async function verifyChecksums(releaseDir, manifest) {
  const checksumFile = path.join(releaseDir, "SHA256SUMS");
  const text = await readFile(checksumFile, "utf8").catch(() => fail("SHA256SUMS is required"));
  const entries = new Map();
  for (const [index, line] of text.trimEnd().split("\n").entries()) {
    const match = /^([0-9a-f]{64})  ([^/]+)$/.exec(line);
    if (!match || entries.has(match[2])) fail(`invalid or duplicate SHA256SUMS entry at line ${index + 1}`);
    entries.set(match[2], match[1]);
  }
  const expectedNames = [manifestName, ...manifest.artifacts.map(({ name }) => name)].sort();
  if (JSON.stringify([...entries.keys()].sort()) !== JSON.stringify(expectedNames)) {
    fail("SHA256SUMS does not exactly cover the release manifest and payload artifacts");
  }
  for (const name of expectedNames) {
    const actual = await sha256(path.join(releaseDir, name));
    if (entries.get(name) !== actual) fail(`SHA256SUMS mismatch: ${name}`);
  }
}

const options = parseArgs(process.argv.slice(2));
const releaseDir = path.resolve(options.releaseDir);
const expected = await buildManifest(releaseDir, options.tag, options.gitHead, options.requireEvidence);
const manifestPath = path.join(releaseDir, manifestName);

if (options.command === "write") {
  const temporary = `${manifestPath}.tmp`;
  await writeFile(temporary, stableJson(expected), { mode: 0o644 });
  await rename(temporary, manifestPath);
  console.log(`Wrote release asset manifest: ${manifestPath}`);
} else {
  const actualText = await readFile(manifestPath, "utf8").catch(() => fail(`missing ${manifestName}`));
  let actual;
  try {
    actual = JSON.parse(actualText);
  } catch (error) {
    fail(`${manifestName} is invalid JSON: ${error.message}`);
  }
  if (stableJson(actual) !== stableJson(expected)) fail(`${manifestName} does not match the release directory`);
  if (options.requireChecksum) await verifyChecksums(releaseDir, expected);
  console.log(`Release asset manifest verified: ${expected.artifacts.length} artifacts for ${options.tag}`);
}
