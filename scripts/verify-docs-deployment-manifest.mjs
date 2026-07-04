#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, lstatSync, readdirSync, readFileSync, statSync } from "node:fs";
import { isAbsolute, join, relative, sep } from "node:path";

const args = process.argv.slice(2);
const manifestPath = readOption("--manifest");
const distDir = readOption("--dist") ?? "apps/docs/docs/.vitepress/dist";
const expectedStorageZone = readOption("--storage-zone");
const expectedStorageEndpoint = readOption("--storage-endpoint");
const expectedRemotePrefix = readOption("--remote-prefix");
const expectedDryRun = readOption("--expected-dry-run");

if (args.includes("-h") || args.includes("--help")) {
  usage();
  process.exit(0);
}

validateArgs();

if (!manifestPath) {
  usage();
  process.exit(2);
}

if (!existsSync(distDir) || !statSync(distDir).isDirectory()) {
  fail(`docs dist directory does not exist: ${distDir}`);
}

const manifest = readJson(manifestPath);
const distFiles = collectDistFiles(distDir);
const uploads = validateManifestShape(manifest);
const uploadMap = new Map();

for (const upload of uploads) {
  validateUpload(upload);
  if (uploadMap.has(upload.relativePath)) {
    fail(`duplicate upload path in manifest: ${upload.relativePath}`);
  }
  uploadMap.set(upload.relativePath, upload);
}

if (manifest.fileCount !== uploads.length) {
  fail(`manifest fileCount ${manifest.fileCount} does not match upload count ${uploads.length}`);
}

if (uploads.length !== distFiles.length) {
  fail(`manifest upload count ${uploads.length} does not match dist file count ${distFiles.length}`);
}

for (const distFile of distFiles) {
  const upload = uploadMap.get(distFile.relativePath);
  if (!upload) {
    fail(`manifest is missing dist file: ${distFile.relativePath}`);
  }

  const expectedRemotePath = remotePathFor(distFile.relativePath, manifest.storage.remotePrefix);
  if (upload.remotePath !== expectedRemotePath) {
    fail(`remote path mismatch for ${distFile.relativePath}: expected ${expectedRemotePath}, got ${upload.remotePath}`);
  }

  if (upload.checksumSha256 !== distFile.checksumSha256) {
    fail(`checksum mismatch for ${distFile.relativePath}`);
  }
}

for (const relativePath of uploadMap.keys()) {
  if (!distFiles.some((file) => file.relativePath === relativePath)) {
    fail(`manifest includes a file that is not in dist: ${relativePath}`);
  }
}

for (const requiredFile of ["index.html", "install.sh"]) {
  if (!manifest.requiredFiles.includes(requiredFile)) {
    fail(`manifest requiredFiles is missing ${requiredFile}`);
  }

  const filePath = join(distDir, requiredFile);
  if (!existsSync(filePath) || statSync(filePath).size === 0) {
    fail(`docs dist is missing required file: ${requiredFile}`);
  }
}

rejectSecretLikeKeys(manifest);

console.log(`Docs deployment manifest verified: ${manifestPath} (${uploads.length} files).`);

function usage() {
  console.log(`Verify a Loopwire docs deployment manifest against a built VitePress dist.

Usage:
  verify-docs-deployment-manifest.mjs --manifest FILE [--dist DIR]
    [--storage-zone ZONE] [--storage-endpoint URL] [--remote-prefix PATH]
    [--expected-dry-run true|false]

Checks:
  - manifest schema and generated timestamp,
  - storage zone, endpoint, and remote prefix path safety,
  - required index.html and install.sh entries,
  - every dist file appears exactly once,
  - every SHA-256 checksum matches current dist bytes,
  - every remote path matches the configured prefix,
  - manifest keys do not include secret-like fields.
`);
}

function readOption(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function validateArgs() {
  const valueOptions = new Set([
    "--manifest",
    "--dist",
    "--storage-zone",
    "--storage-endpoint",
    "--remote-prefix",
    "--expected-dry-run"
  ]);
  const flagOptions = new Set(["--", "-h", "--help"]);

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (valueOptions.has(arg)) {
      if (index + 1 >= args.length || args[index + 1].startsWith("--")) {
        fail(`missing value for ${arg}`, 2);
      }
      if (args[index + 1] === "" && arg !== "--remote-prefix") {
        fail(`missing value for ${arg}`, 2);
      }
      index += 1;
      continue;
    }

    if (flagOptions.has(arg)) {
      continue;
    }

    fail(`unknown argument: ${arg}`, 2);
  }

  if (expectedDryRun && !["true", "false"].includes(expectedDryRun)) {
    fail("--expected-dry-run must be true or false", 2);
  }
}

function fail(message, code = 1) {
  console.error(`verify-docs-deployment-manifest: ${message}`);
  process.exit(code);
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`failed to read JSON: ${path}: ${error.message}`);
  }
}

function validateManifestShape(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("manifest root must be an object");
  }

  if (value.schema !== "loopwire.docs-deployment.v1") {
    fail(`unsupported manifest schema: ${value.schema ?? "<missing>"}`);
  }

  if (typeof value.generatedAt !== "string" || Number.isNaN(Date.parse(value.generatedAt))) {
    fail("manifest generatedAt must be an ISO timestamp");
  }

  if (typeof value.dryRun !== "boolean") {
    fail("manifest dryRun must be a boolean");
  }

  if (expectedDryRun && value.dryRun !== (expectedDryRun === "true")) {
    fail(`manifest dryRun mismatch: expected ${expectedDryRun}, got ${value.dryRun}`);
  }

  if (typeof value.distDir !== "string" || value.distDir.length === 0) {
    fail("manifest distDir must be a non-empty string");
  }

  validateStorage(value.storage);

  if (!Array.isArray(value.requiredFiles)) {
    fail("manifest requiredFiles must be an array");
  }

  if (!Number.isInteger(value.fileCount) || value.fileCount < 1) {
    fail("manifest fileCount must be a positive integer");
  }

  if (!Array.isArray(value.uploads) || value.uploads.length === 0) {
    fail("manifest uploads must be a non-empty array");
  }

  return value.uploads;
}

function validateStorage(storage) {
  if (!storage || typeof storage !== "object" || Array.isArray(storage)) {
    fail("manifest storage must be an object");
  }

  validateSingleLine(storage.zone, "storage zone");
  if (storage.zone.includes("/")) {
    fail("storage zone must not contain slashes");
  }

  validateSingleLine(storage.endpoint, "storage endpoint");
  if (!/^https?:\/\//.test(storage.endpoint)) {
    fail("storage endpoint must start with http:// or https://");
  }

  validateSingleLine(storage.remotePrefix, "remote prefix", true);
  validateRemotePrefix(storage.remotePrefix);

  if (expectedStorageZone && storage.zone !== expectedStorageZone) {
    fail(`storage zone mismatch: expected ${expectedStorageZone}, got ${storage.zone}`);
  }

  if (expectedStorageEndpoint && storage.endpoint !== normalizeEndpoint(expectedStorageEndpoint)) {
    fail(`storage endpoint mismatch: expected ${normalizeEndpoint(expectedStorageEndpoint)}, got ${storage.endpoint}`);
  }

  if (expectedRemotePrefix !== undefined && storage.remotePrefix !== normalizeRemotePrefix(expectedRemotePrefix)) {
    const expected = normalizeRemotePrefix(expectedRemotePrefix);
    fail(`remote prefix mismatch: expected ${expected}, got ${storage.remotePrefix}`);
  }
}

function validateUpload(upload) {
  if (!upload || typeof upload !== "object" || Array.isArray(upload)) {
    fail("manifest upload entry must be an object");
  }

  validateRelativePath(upload.relativePath, "upload relativePath");
  validateRelativePath(upload.remotePath, "upload remotePath");

  if (typeof upload.checksumSha256 !== "string" || !/^[A-F0-9]{64}$/.test(upload.checksumSha256)) {
    fail(`invalid SHA-256 checksum for ${upload.relativePath ?? "<missing>"}`);
  }
}

function validateSingleLine(value, label, allowEmpty = false) {
  if (typeof value !== "string" || (!allowEmpty && value.length === 0)) {
    fail(`${label} must be a ${allowEmpty ? "string" : "non-empty string"}`);
  }

  if (value.includes("\0") || /[\r\n\t]/.test(value)) {
    fail(`${label} must not contain control separators`);
  }
}

function validateRelativePath(value, label) {
  validateSingleLine(value, label);

  if (isAbsolute(value) || value.includes("\\") || value.startsWith("/")) {
    fail(`${label} must be a relative POSIX path: ${value}`);
  }

  const segments = value.split("/");
  if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) {
    fail(`${label} must not contain empty, . or .. segments: ${value}`);
  }
}

function validateRemotePrefix(prefix) {
  if (prefix === "") {
    return;
  }

  validateRelativePath(prefix, "remote prefix");
}

function normalizeEndpoint(endpoint) {
  validateSingleLine(endpoint, "expected storage endpoint");
  return (endpoint.startsWith("http://") || endpoint.startsWith("https://") ? endpoint : `https://${endpoint}`)
    .replace(/\/+$/, "");
}

function normalizeRemotePrefix(prefix) {
  validateSingleLine(prefix, "expected remote prefix", true);
  const trimmed = prefix.replace(/^\/+/, "").replace(/\/+$/, "");
  validateRemotePrefix(trimmed);
  return trimmed;
}

function remotePathFor(relativePath, prefix) {
  return prefix ? `${prefix}/${relativePath}` : relativePath;
}

function collectDistFiles(dir) {
  return walk(dir)
    .map((path) => {
      const relativePath = relative(dir, path).split(sep).join("/");
      validateRelativePath(relativePath, "dist relative path");
      return {
        relativePath,
        checksumSha256: checksum(path)
      };
    })
    .sort((left, right) => left.relativePath.localeCompare(right.relativePath));
}

function walk(dir) {
  const entries = readdirSync(dir, { withFileTypes: true });
  const paths = [];

  for (const entry of entries) {
    const path = join(dir, entry.name);
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) {
      fail(`docs dist must not contain symlinks: ${path}`);
    }

    if (entry.isDirectory()) {
      paths.push(...walk(path));
    } else if (entry.isFile()) {
      paths.push(path);
    }
  }

  return paths;
}

function checksum(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex").toUpperCase();
}

function rejectSecretLikeKeys(value, path = "manifest") {
  if (!value || typeof value !== "object") {
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    if (/(access.?key|authorization|credential|password|secret|token)/i.test(key)) {
      fail(`manifest contains secret-like key: ${path}.${key}`);
    }
    rejectSecretLikeKeys(child, `${path}.${key}`);
  }
}
