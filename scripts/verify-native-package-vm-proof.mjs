#!/usr/bin/env node

import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";

function fail(message) {
  console.error(`verify-native-package-vm-proof: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!["--target", "--evidence-dir", "--git-head"].includes(argument)) {
      fail(`unknown argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`missing value for ${argument}`);
    result[argument.slice(2)] = value;
    index += 1;
  }
  return result;
}

function parseTsvMap(text, label) {
  const result = new Map();
  for (const [index, line] of text.trimEnd().split("\n").entries()) {
    if (!line) continue;
    const separator = line.indexOf("\t");
    if (separator < 1) fail(`${label} line ${index + 1} is not key/value TSV`);
    const key = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (result.has(key)) fail(`${label} repeats key: ${key}`);
    result.set(key, value);
  }
  return result;
}

function requireValue(map, key, expected, label) {
  if (!map.has(key)) fail(`${label} is missing ${key}`);
  if (expected !== undefined && map.get(key) !== expected) {
    fail(`${label} ${key} must be ${JSON.stringify(expected)}, got ${JSON.stringify(map.get(key))}`);
  }
  return map.get(key);
}

function parseOsRelease(text) {
  const result = new Map();
  for (const line of text.split("\n")) {
    const match = /^([A-Z_]+)=(.*)$/.exec(line);
    if (!match) continue;
    let value = match[2];
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.slice(1, -1).replaceAll('\\"', '"');
    }
    result.set(match[1], value);
  }
  return result;
}

async function textFile(directory, name) {
  const file = path.join(directory, name);
  let stat;
  try {
    stat = await lstat(file);
  } catch {
    fail(`missing evidence file: ${name}`);
  }
  if (!stat.isFile() || stat.isSymbolicLink()) fail(`evidence path must be a regular file: ${name}`);
  return readFile(file, "utf8");
}

async function hashFile(file) {
  const bytes = await readFile(file);
  return createHash("sha256").update(bytes).digest("hex");
}

const args = parseArgs(process.argv.slice(2));
const target = args.target;
const evidenceDir = args["evidence-dir"];
const gitHead = args["git-head"];
if (!target) fail("--target is required");
if (!evidenceDir) fail("--evidence-dir is required");
if (!/^[0-9a-f]{40}$/.test(gitHead ?? "")) fail("--git-head must be a full lowercase commit hash");

const targetRows = (await readFile("packaging/vm/native-package-targets.tsv", "utf8"))
  .split("\n")
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.split("\t"));
const rows = targetRows.filter((row) => row[0] === target);
if (rows.length !== 1) fail(`target must occur exactly once in manifest: ${target}`);
const [id, distro, packageTarget, format, imageUrl, checksumAlgorithm, checksum, , firmware] = rows[0];
if (rows[0].length !== 9) fail(`${target} manifest row must contain nine fields`);

const expectedTargets = {
  "ubuntu-24.04": { osId: "ubuntu", versionId: "24.04", arch: "amd64", packageSuffix: "-1ubuntu24.04" },
  "debian-13": { osId: "debian", versionId: "13", arch: "amd64", packageSuffix: "-1debian13" },
  "fedora-44": { osId: "fedora", versionId: "44", arch: "x86_64", packageSuffix: "-1.fc44" },
  "opensuse-tumbleweed": { osId: "opensuse-tumbleweed", versionId: null, arch: "x86_64", packageSuffix: "-1" },
};
const expected = expectedTargets[target];
if (!expected) fail(`unsupported target: ${target}`);

const summary = parseTsvMap(await textFile(evidenceDir, "summary.tsv"), "summary.tsv");
requireValue(summary, "schema", "loopwire.native-package-vm-proof.v1", "summary.tsv");
requireValue(summary, "target", id, "summary.tsv");
requireValue(summary, "package_target", packageTarget, "summary.tsv");
requireValue(summary, "format", format, "summary.tsv");
requireValue(summary, "git_head", gitHead, "summary.tsv");
requireValue(summary, "virtualization", undefined, "summary.tsv");
for (const check of ["background_help", "backend_detection", "gui_linkage", "gui_launch", "uninstall"]) {
  requireValue(summary, check, "pass", "summary.tsv");
}
const version = requireValue(summary, "version", undefined, "summary.tsv");
if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:[+~.-][0-9A-Za-z.+~_-]+)?$/.test(version)) {
  fail(`summary.tsv has invalid version: ${version}`);
}

const image = parseTsvMap(await textFile(evidenceDir, "image.tsv"), "image.tsv");
requireValue(image, "schema", "loopwire.native-package-image.v1", "image.tsv");
requireValue(image, "target", id, "image.tsv");
requireValue(image, "distro", distro, "image.tsv");
requireValue(image, "url", imageUrl, "image.tsv");
requireValue(image, "checksum_algorithm", checksumAlgorithm, "image.tsv");
requireValue(image, "checksum", checksum, "image.tsv");
requireValue(image, "actual_checksum", checksum, "image.tsv");
requireValue(image, "firmware", firmware, "image.tsv");

if ((await textFile(evidenceDir, "git-head.txt")).trim() !== gitHead) fail("git-head.txt does not match --git-head");
const virtualization = (await textFile(evidenceDir, "virtualization.txt")).trim();
if (!["kvm", "qemu"].includes(virtualization)) fail(`unexpected virtualization: ${virtualization}`);
requireValue(summary, "virtualization", virtualization, "summary.tsv");

const osRelease = parseOsRelease(await textFile(evidenceDir, "os-release"));
if (osRelease.get("ID") !== expected.osId) fail(`guest ID must be ${expected.osId}, got ${osRelease.get("ID")}`);
if (expected.versionId && osRelease.get("VERSION_ID") !== expected.versionId) {
  fail(`guest VERSION_ID must be ${expected.versionId}, got ${osRelease.get("VERSION_ID")}`);
}
if (!osRelease.get("VERSION_ID")) fail("guest VERSION_ID is missing");
if (!(await textFile(evidenceDir, "uname.txt")).includes("Linux")) fail("uname.txt does not describe a Linux guest");

const packageName = requireValue(summary, "package", undefined, "summary.tsv");
const expectedName = format === "deb"
  ? `loopwire_${version}${expected.packageSuffix}_${expected.arch}.deb`
  : `loopwire-${version}${expected.packageSuffix}.${expected.arch}.rpm`;
if (packageName !== expectedName) fail(`package filename must be ${expectedName}, got ${packageName}`);
const files = await readdir(evidenceDir);
const packageFiles = files.filter((name) => name.endsWith(`.${format}`));
if (packageFiles.length !== 1 || packageFiles[0] !== packageName) {
  fail(`evidence must contain exactly the declared .${format} package`);
}
const packageHash = await hashFile(path.join(evidenceDir, packageName));
requireValue(summary, "package_sha256", packageHash, "summary.tsv");
const checksumLine = (await textFile(evidenceDir, "package.sha256")).trim();
const checksumMatch = /^([0-9a-f]{64})\s+(.+)$/.exec(checksumLine);
if (!checksumMatch || checksumMatch[1] !== packageHash || path.basename(checksumMatch[2]) !== packageName) {
  fail("package.sha256 does not bind the declared package and checksum");
}

const metadata = (await textFile(evidenceDir, "package-metadata.tsv")).trim().split("\t");
if (metadata.length < 3 || metadata[0] !== "loopwire") fail("package metadata has the wrong name or shape");
if (metadata[1] !== `${version}${expected.packageSuffix}`) {
  fail(`installed package version must be ${version}${expected.packageSuffix}, got ${metadata[1]}`);
}
if (metadata[2] !== expected.arch) fail(`installed package architecture must be ${expected.arch}, got ${metadata[2]}`);
if (format === "deb" && metadata[3] !== "install ok installed") fail("dpkg did not report an installed package");

const installedFiles = await textFile(evidenceDir, "package-files.txt");
for (const installed of [
  "/usr/bin/loopwire",
  "/usr/bin/loopwire-dsp-provider",
  "/usr/bin/loopwire-jack-ports",
  "/usr/bin/loopwire-detect-audio",
  "/usr/lib/loopwire/loopwire-gui",
  "/usr/share/applications/loopwire.desktop",
  "/usr/share/icons/hicolor/scalable/apps/loopwire.svg",
]) {
  if (!installedFiles.split("\n").includes(installed)) fail(`package file list is missing ${installed}`);
}

for (const helpFile of ["background-help.txt", "dsp-provider-help.txt", "jack-provider-help.txt"]) {
  if (!(await textFile(evidenceDir, helpFile)).trim()) fail(`${helpFile} is empty`);
}
try {
  const detection = JSON.parse(await textFile(evidenceDir, "detect-audio.json"));
  if (!detection || typeof detection !== "object") fail("detect-audio.json must contain an object or array");
} catch (error) {
  fail(`detect-audio.json is invalid JSON: ${error.message}`);
}
if ((await textFile(evidenceDir, "gui-ldd.txt")).includes("not found")) fail("GUI has unresolved shared libraries");
if ((await textFile(evidenceDir, "gui-launch-status.txt")).trim() !== "0") fail("GUI launch did not exit successfully");
if (!/^\d+(?:\n\d+)*\n?$/.test(await textFile(evidenceDir, "gui-window-ids.txt"))) {
  fail("GUI proof does not contain a Loopwire X11 window id");
}
const windowNames = (await textFile(evidenceDir, "gui-window-names.txt")).trim().split("\n");
if (windowNames.length === 0 || windowNames.some((name) => !/^(Loopwire|loopwire-gui)$/.test(name))) {
  fail("GUI proof does not contain an application-specific Loopwire X11 window name");
}
const guiLog = await textFile(evidenceDir, "gui-launch.log");
if (/error while loading shared libraries|panic|protocol error|missing acquire timeline/i.test(guiLog)) {
  fail("GUI launch log contains a fatal signature");
}
if ((await textFile(evidenceDir, "uninstall-status.txt")).trim() !== "removed") fail("uninstall proof is missing");

console.log(`Native package VM proof verified: ${target}`);
console.log(`Guest: ${osRelease.get("PRETTY_NAME") ?? `${expected.osId} ${osRelease.get("VERSION_ID")}`}`);
console.log(`Package: ${packageName} (${packageHash})`);
console.log(`Commit: ${gitHead}`);
