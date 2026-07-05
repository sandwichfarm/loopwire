#!/usr/bin/env node
import { existsSync, lstatSync, readFileSync } from "node:fs";

const args = process.argv.slice(2);

if (args.includes("-h") || args.includes("--help")) {
  usage();
  process.exit(0);
}

const manifestPath = readOption("--manifest");
const releaseTag = readOption("--tag");
const targetsFile = readOption("--targets-file");
const expectedTargets = readOptions("--target");
const requirePublishedRelease = args.includes("--require-published-release");
const requireAllTargets = args.includes("--require-all-targets");

if (!manifestPath) fail("missing --manifest FILE");
if (!releaseTag) fail("missing --tag vX.Y.Z");
validateLocalFile(manifestPath, "manifest");
validateTag(releaseTag);

let targets = expectedTargets;
if (targetsFile) {
  validateLocalFile(targetsFile, "targets file");
  targets = readTargetsFile(targetsFile);
}

if (requireAllTargets && targets.length === 0) {
  fail("--require-all-targets requires --target or --targets-file");
}

const manifest = readJson(manifestPath, "manifest");
const errors = [];

if (manifest.kind !== "loopwire.vm-evidence-archive") {
  errors.push(`kind must be loopwire.vm-evidence-archive, found ${stringifyValue(manifest.kind)}`);
}

if (manifest.version !== 1) {
  errors.push(`version must be 1, found ${stringifyValue(manifest.version)}`);
}

if (manifest.tag !== releaseTag) {
  errors.push(`tag must be ${releaseTag}, found ${stringifyValue(manifest.tag)}`);
}

if (manifest.layout !== "vm-evidence/<target>") {
  errors.push(`layout must be vm-evidence/<target>, found ${stringifyValue(manifest.layout)}`);
}

if (typeof manifest.generatedAt !== "string" || Number.isNaN(Date.parse(manifest.generatedAt))) {
  errors.push("generatedAt must be an ISO timestamp string");
}

if (requirePublishedRelease && manifest.requirePublishedRelease !== true) {
  errors.push("requirePublishedRelease must be true");
}

if (!Array.isArray(manifest.targets)) {
  errors.push("targets must be an array");
} else {
  const seen = new Set();
  for (const target of manifest.targets) {
    if (typeof target !== "string" || target.length === 0) {
      errors.push(`targets must contain non-empty strings, found ${stringifyValue(target)}`);
      continue;
    }
    if (seen.has(target)) {
      errors.push(`targets contains duplicate target: ${target}`);
    }
    seen.add(target);
  }

  if (manifest.targetCount !== manifest.targets.length) {
    errors.push(`targetCount must equal targets length ${manifest.targets.length}, found ${stringifyValue(manifest.targetCount)}`);
  }

  if (targets.length > 0) {
    const expectedSet = new Set(targets);
    const manifestSet = new Set(manifest.targets);
    for (const target of targets) {
      if (!manifestSet.has(target)) {
        errors.push(`manifest missing expected target: ${target}`);
      }
    }
    for (const target of manifest.targets) {
      if (!expectedSet.has(target)) {
        errors.push(`manifest contains unexpected target: ${target}`);
      }
    }
    if (requireAllTargets && manifest.targets.join("\n") !== targets.join("\n")) {
      errors.push("manifest target order must match targets file order");
    }
  }
}

if (errors.length > 0) {
  errors.forEach((error) => console.error(`verify-vm-evidence-archive-manifest: ${error}`));
  process.exit(1);
}

console.log(`VM evidence archive manifest verified: ${manifest.targets.length} target(s) for ${releaseTag}.`);

function usage() {
  console.log(`Verify the root manifest for a packaged Loopwire VM evidence archive.

Usage:
  verify-vm-evidence-archive-manifest.mjs --manifest FILE --tag vX.Y.Z
    [--target TARGET ... | --targets-file FILE --require-all-targets]
    [--require-published-release]

The manifest must identify the archive kind, release tag, deterministic vm-evidence/<target> layout, selected targets,
and whether the archive was built with published-release evidence strictness.`);
}

function readOption(name) {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) fail(`missing value for ${name}`);
  return value;
}

function readOptions(name) {
  const values = [];
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === name) {
      const value = args[index + 1];
      if (!value || value.startsWith("--")) fail(`missing value for ${name}`);
      values.push(value);
      index += 1;
    }
  }
  return values;
}

function fail(message) {
  console.error(`verify-vm-evidence-archive-manifest: ${message}`);
  process.exit(1);
}

function validateTag(value) {
  const pattern = /^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$/;
  if (!pattern.test(value)) {
    fail(`tag must be v-prefixed semver without path separators: ${value}`);
  }
}

function validateLocalFile(value, label) {
  if (value.includes("\n") || value.includes("\r")) {
    fail(`${label} path must be a single safe value`);
  }
  if (
    value.length === 0 ||
    value === "/" ||
    value.startsWith("~/") ||
    value.includes("://") ||
    value.includes("*") ||
    value.includes("?") ||
    value.includes("[") ||
    value.includes("]")
  ) {
    fail(`${label} path must be a local file path without root/home placeholders, URLs, or glob metacharacters`);
  }
  const segments = value.split("/");
  if (segments.includes(".") || segments.includes("..")) {
    fail(`${label} path must not contain . or .. path segments`);
  }
  if (!existsSync(value)) {
    fail(`missing ${label}: ${value}`);
  }
  const stat = lstatSync(value);
  if (stat.isSymbolicLink() || !stat.isFile()) {
    fail(`${label} must be a regular file: ${value}`);
  }
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`cannot parse ${label} JSON: ${error.message}`);
  }
}

function readTargetsFile(path) {
  const targets = [];
  const content = readFileSync(path, "utf8");
  for (const line of content.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue;
    const [target] = line.split("\t");
    if (target) targets.push(target);
  }
  return targets;
}

function stringifyValue(value) {
  return JSON.stringify(value);
}
