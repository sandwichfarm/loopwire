#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const evidenceRoot = readOption("--evidence-root") ?? join(root, ".vm/evidence");
const matrixPath = readOption("--matrix") ?? join(root, "apps/docs/docs/guide/support-matrix.md");
const requirePublishedRelease = args.includes("--require-published-release");
const allowedStatuses = new Set(["Manual VM", "Verified"]);

if (args.includes("-h") || args.includes("--help")) {
  usage();
  process.exit(0);
}

validateArgs();

const targets = readTargets(join(root, "vm/targets.tsv"));
const rows = readMatrixRows(matrixPath);
const errors = [];
let evidenceBacked = 0;

if (targets.length !== rows.length) {
  errors.push(`host target row count mismatch: docs=${rows.length}, targets=${targets.length}`);
}

targets.forEach((target, index) => {
  const row = rows[index];
  if (!row) {
    errors.push(`missing support matrix row for ${target.id}`);
    return;
  }

  if (row.id !== target.id) {
    errors.push(`row ${index + 1} target mismatch: expected ${target.id}, found ${row.id}`);
  }

  const expectedDesktop = `${target.desktop} on ${target.session}`;
  if (row.desktopSession !== expectedDesktop) {
    errors.push(`${target.id} desktop/session mismatch: expected "${expectedDesktop}", found "${row.desktopSession}"`);
  }

  if (row.audio !== target.audio) {
    errors.push(`${target.id} audio mismatch: expected "${target.audio}", found "${row.audio}"`);
  }

  if (!allowedStatuses.has(row.status)) {
    errors.push(`${target.id} has unsupported status: ${row.status}`);
  }

  const evidenceDir = join(evidenceRoot, target.id);
  const hasEvidenceDir = existsSync(evidenceDir);
  const evidenceVerified = hasEvidenceDir && verifyEvidence(target.id, evidenceDir);

  if (row.status === "Verified" && !evidenceVerified) {
    errors.push(`${target.id} is marked Verified but has no verified evidence bundle at ${evidenceDir}`);
  }

  if (row.status === "Manual VM" && evidenceVerified) {
    errors.push(`${target.id} has verified evidence at ${evidenceDir}; update support matrix status to Verified`);
  }

  if (evidenceVerified) {
    evidenceBacked += 1;
  }
});

const extraRows = rows.slice(targets.length);
extraRows.forEach((row) => errors.push(`unexpected support matrix row: ${row.id}`));

if (errors.length > 0) {
  errors.forEach((error) => console.error(`verify-support-matrix: ${error}`));
  process.exit(1);
}

console.log(`Support matrix verified: ${targets.length} targets, ${evidenceBacked} evidence-backed.`);

function usage() {
  console.log(`Verify Loopwire support matrix rows against VM target metadata and evidence.

Usage:
  verify-support-matrix.mjs [--evidence-root DIR] [--matrix FILE] [--require-published-release]

Rows marked Verified require a passing target evidence bundle. Rows with passing evidence must be marked Verified.
Use --require-published-release for final release support claims that must prove installed-release smoke.
`);
}

function readOption(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function validateArgs() {
  const valueOptions = new Set(["--evidence-root", "--matrix"]);
  const flagOptions = new Set(["--require-published-release"]);

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (valueOptions.has(arg)) {
      if (!args[index + 1] || args[index + 1].startsWith("--")) {
        console.error(`verify-support-matrix: missing value for ${arg}`);
        process.exit(2);
      }

      index += 1;
      continue;
    }

    if (flagOptions.has(arg)) {
      continue;
    }

    console.error(`verify-support-matrix: unknown argument: ${arg}`);
    process.exit(2);
  }
}

function readTargets(path) {
  return readFileSync(path, "utf8")
    .split("\n")
    .filter((line) => line.trim() && !line.trim().startsWith("#"))
    .map((line) => {
      const [id, _distro, _family, desktop, session, audio] = line.split("\t");
      return { id, desktop, session, audio };
    });
}

function readMatrixRows(path) {
  const markdown = readFileSync(path, "utf8");
  const hostSection = markdown.split("## Host Targets")[1]?.split(/\n## /)[0];
  if (!hostSection) {
    throw new Error("support matrix is missing ## Host Targets");
  }

  return hostSection
    .split("\n")
    .filter((line) => line.trim().startsWith("| `"))
    .map((line) => {
      const cells = line.split("|").slice(1, -1).map((cell) => cell.trim());
      const id = cells[0]?.match(/`([^`]+)`/)?.[1] ?? "";
      return {
        id,
        desktopSession: cells[1] ?? "",
        audio: cells[2] ?? "",
        status: cells[3] ?? ""
      };
    });
}

function verifyEvidence(target, evidenceDir) {
  const verifierArgs = ["scripts/verify-vm-evidence.sh", "--target", target, "--evidence-dir", evidenceDir];
  if (requirePublishedRelease) {
    verifierArgs.push("--require-published-release");
  }

  const result = spawnSync(
    "bash",
    verifierArgs,
    { cwd: root, encoding: "utf8", maxBuffer: 1024 * 1024 }
  );

  if (result.status !== 0) {
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
    errors.push(`${target} evidence bundle failed verification: ${output}`);
    return false;
  }

  return true;
}
