#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";

function fail(message) {
  console.error(`verify-native-package-proof-snapshot: ${message}`);
  process.exit(1);
}

const argv = process.argv.slice(2);
let root = "vm/native-package-proof";
while (argv.length > 0) {
  const argument = argv.shift();
  if (argument === "--root") root = argv.shift() ?? fail("missing value for --root");
  else if (argument === "--help" || argument === "-h") {
    console.log("Usage: verify-native-package-proof-snapshot.mjs [--root vm/native-package-proof]");
    process.exit(0);
  } else fail(`unknown argument: ${argument}`);
}

async function textFile(directory, name) {
  const file = path.join(directory, name);
  let stat;
  try {
    stat = await lstat(file);
  } catch {
    fail(`missing snapshot file: ${file}`);
  }
  if (!stat.isFile() || stat.isSymbolicLink()) fail(`snapshot path must be a regular file: ${file}`);
  return readFile(file, "utf8");
}

function parseTsv(text, label) {
  const result = new Map();
  for (const line of text.trimEnd().split("\n")) {
    const [key, ...values] = line.split("\t");
    if (!key || values.length !== 1 || result.has(key)) fail(`${label} is not unique key/value TSV`);
    result.set(key, values[0]);
  }
  return result;
}

function requireValue(map, key, expected, label) {
  const value = map.get(key);
  if (value === undefined) fail(`${label} is missing ${key}`);
  if (expected !== undefined && value !== expected) fail(`${label} ${key} must be ${expected}, got ${value}`);
  return value;
}

const manifest = (await readFile("packaging/vm/native-package-targets.tsv", "utf8"))
  .split("\n")
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.split("\t"));
if (manifest.length !== 4 || manifest.some((row) => row.length !== 9)) fail("native target manifest is invalid");
const expectedEntries = ["README.md", ...manifest.map((row) => row[0])].sort();
const entries = (await readdir(root)).sort();
if (JSON.stringify(entries) !== JSON.stringify(expectedEntries)) fail("snapshot root does not exactly cover the manifest");
const requiredSnapshotFiles = [
  "background-help.txt",
  "detect-audio.json",
  "dsp-provider-help.txt",
  "git-head.txt",
  "gui-launch-status.txt",
  "gui-ldd.txt",
  "gui-window-ids.txt",
  "gui-window-names.txt",
  "image.tsv",
  "jack-provider-help.txt",
  "os-release",
  "package-files.txt",
  "package-metadata.tsv",
  "package.sha256",
  "summary.tsv",
  "uname.txt",
  "uninstall-status.txt",
  "virtualization.txt",
].sort();

let sharedCommit;
for (const [target, distro, packageTarget, format, imageUrl, algorithm, imageChecksum, , firmware] of manifest) {
  const directory = path.join(root, target);
  const targetFiles = (await readdir(directory)).sort();
  if (JSON.stringify(targetFiles) !== JSON.stringify(requiredSnapshotFiles)) {
    fail(`${target} snapshot files do not match the review-safe allowlist`);
  }
  const snapshotText = (await Promise.all(targetFiles.map((file) => textFile(directory, file)))).join("\n");
  if (/\/home\/sandwich|BEGIN [A-Z ]*PRIVATE KEY|ssh-ed25519/i.test(snapshotText)) {
    fail(`${target} snapshot contains host paths or key material`);
  }
  const summary = parseTsv(await textFile(directory, "summary.tsv"), `${target}/summary.tsv`);
  const image = parseTsv(await textFile(directory, "image.tsv"), `${target}/image.tsv`);
  requireValue(summary, "schema", "loopwire.native-package-vm-proof.v1", target);
  requireValue(summary, "target", target, target);
  requireValue(summary, "package_target", packageTarget, target);
  requireValue(summary, "format", format, target);
  requireValue(summary, "virtualization", "kvm", target);
  for (const check of ["background_help", "backend_detection", "gui_linkage", "gui_launch", "uninstall"]) {
    requireValue(summary, check, "pass", target);
  }
  const commit = requireValue(summary, "git_head", undefined, target);
  if (!/^[0-9a-f]{40}$/.test(commit)) fail(`${target} has invalid git head`);
  if (sharedCommit && commit !== sharedCommit) fail("snapshot targets do not share one tested commit");
  sharedCommit = commit;
  if ((await textFile(directory, "git-head.txt")).trim() !== commit) fail(`${target} git-head.txt mismatch`);
  requireValue(image, "schema", "loopwire.native-package-image.v1", target);
  requireValue(image, "target", target, target);
  requireValue(image, "distro", distro, target);
  requireValue(image, "url", imageUrl, target);
  requireValue(image, "checksum_algorithm", algorithm, target);
  requireValue(image, "checksum", imageChecksum, target);
  requireValue(image, "actual_checksum", imageChecksum, target);
  requireValue(image, "firmware", firmware, target);
  const packageName = requireValue(summary, "package", undefined, target);
  const packageSha = requireValue(summary, "package_sha256", undefined, target);
  if (!/^[0-9a-f]{64}$/.test(packageSha)) fail(`${target} has invalid package SHA-256`);
  if ((await textFile(directory, "package.sha256")).trim() !== `${packageSha}  ${packageName}`) {
    fail(`${target} package checksum snapshot mismatch`);
  }
  if (!(await textFile(directory, "package-metadata.tsv")).startsWith("loopwire\t")) {
    fail(`${target} package metadata is missing loopwire`);
  }
  if (!(await textFile(directory, "package-files.txt")).split("\n").includes("/usr/lib/loopwire/loopwire-gui")) {
    fail(`${target} package file list is missing the GUI`);
  }
  JSON.parse(await textFile(directory, "detect-audio.json"));
  if ((await textFile(directory, "gui-ldd.txt")).includes("not found")) fail(`${target} GUI linkage is unresolved`);
  if ((await textFile(directory, "gui-launch-status.txt")).trim() !== "0") fail(`${target} GUI launch status failed`);
  if (!/^(Loopwire|loopwire-gui)(?:\n(Loopwire|loopwire-gui))*\n?$/.test(await textFile(directory, "gui-window-names.txt"))) {
    fail(`${target} GUI window name is invalid`);
  }
  if ((await textFile(directory, "uninstall-status.txt")).trim() !== "removed") fail(`${target} uninstall failed`);
  if ((await textFile(directory, "virtualization.txt")).trim() !== "kvm") fail(`${target} is not KVM proof`);
}

try {
  execFileSync("git", ["merge-base", "--is-ancestor", sharedCommit, "HEAD"], { stdio: "ignore" });
} catch {
  fail(`tested commit is not an ancestor of HEAD: ${sharedCommit}`);
}

const proofCriticalPaths = [
  "apps/desktop/package.json",
  "apps/desktop/src",
  "apps/desktop/src-tauri",
  "packages/audio-host",
  "packages/core",
  "packaging/common",
  "packaging/deb",
  "packaging/rpm",
  "packaging/vm/Dockerfile.portable-build",
  "packaging/vm/Dockerfile.qemu",
  "packaging/vm/guest-native-package-smoke.sh",
  "packaging/vm/native-package-targets.tsv",
  "pnpm-lock.yaml",
  "scripts/build-deb-package.sh",
  "scripts/build-portable-linux-binary.sh",
  "scripts/build-rpm-package.sh",
  "scripts/detect-audio-backends.mjs",
  "scripts/extract-safe-tar.sh",
  "scripts/package-release.sh",
  "scripts/restore-background.mjs",
];
try {
  execFileSync("git", ["diff", "--quiet", `${sharedCommit}..HEAD`, "--", ...proofCriticalPaths], {
    stdio: "ignore",
  });
} catch {
  fail(`package or proof-critical inputs changed after tested commit: ${sharedCommit}`);
}

console.log(`Native package proof snapshot verified: ${manifest.length} targets at ${sharedCommit}`);
