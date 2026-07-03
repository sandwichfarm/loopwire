#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const target = readOption("--target");
const evidenceDir = readOption("--evidence-dir") ?? (target ? join(root, ".vm/evidence", target) : "");
const matrixPath = readOption("--matrix") ?? join(root, "apps/docs/docs/guide/support-matrix.md");
const dryRun = args.includes("--dry-run");

if (args.includes("-h") || args.includes("--help")) {
  usage();
  process.exit(0);
}

validateArgs();

if (!target) {
  fail("missing --target TARGET");
}

if (!knownTarget(target)) {
  fail(`unknown VM target: ${target}`);
}

if (!existsSync(evidenceDir)) {
  fail(`missing evidence directory: ${evidenceDir}`);
}

if (!existsSync(matrixPath)) {
  fail(`missing support matrix: ${matrixPath}`);
}

verifyEvidence(target, evidenceDir);

const matrix = readFileSync(matrixPath, "utf8");
const row = findTargetRow(matrix, target);

if (!row) {
  fail(`support matrix has no row for target: ${target}`);
}

if (row.status === "Verified") {
  console.log(`Support matrix already marks ${target} as Verified.`);
  process.exit(0);
}

if (row.status !== "Manual VM") {
  fail(`cannot promote ${target} from unsupported status: ${row.status}`);
}

const nextLine = replaceStatus(row.line, "Verified");

if (dryRun) {
  console.log(`would promote ${target} from Manual VM to Verified in ${matrixPath}`);
  console.log(`evidence verified: ${evidenceDir}`);
  process.exit(0);
}

writeFileSync(matrixPath, replaceLineAt(matrix, row.index, nextLine));
console.log(`Promoted ${target} to Verified in ${matrixPath}.`);

function usage() {
  console.log(`Promote a Loopwire VM support-matrix row after evidence verification.

Usage:
  promote-vm-evidence.mjs --target TARGET [--evidence-dir DIR] [--matrix FILE] [--dry-run]

The tool runs scripts/verify-vm-evidence.sh first. It only promotes rows from Manual VM to Verified.
Use --dry-run to verify evidence and preview the change without editing docs.
`);
}

function readOption(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function validateArgs() {
  const valueOptions = new Set(["--target", "--evidence-dir", "--matrix"]);
  const flagOptions = new Set(["--dry-run"]);

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (valueOptions.has(arg)) {
      if (!args[index + 1] || args[index + 1].startsWith("--")) {
        fail(`missing value for ${arg}`);
      }

      index += 1;
      continue;
    }

    if (flagOptions.has(arg)) {
      continue;
    }

    fail(`unknown argument: ${arg}`);
  }
}

function knownTarget(id) {
  const targetFile = join(root, "vm/targets.tsv");
  return readFileSync(targetFile, "utf8")
    .split(/\r?\n/)
    .some((line) => line && !line.trim().startsWith("#") && line.split("\t")[0] === id);
}

function verifyEvidence(id, dir) {
  const result = spawnSync(
    "bash",
    ["scripts/verify-vm-evidence.sh", "--target", id, "--evidence-dir", dir],
    { cwd: root, encoding: "utf8", maxBuffer: 1024 * 1024 }
  );

  if (result.status !== 0) {
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
    fail(`evidence verification failed for ${id}: ${output || "no output"}`);
  }
}

function findTargetRow(markdown, id) {
  const lines = markdown.split(/\r?\n/);

  for (const [index, line] of lines.entries()) {
    if (!line.startsWith(`| \`${id}\` |`)) {
      continue;
    }

    const cells = line.split("|").slice(1, -1).map((cell) => cell.trim());
    return {
      index,
      line,
      status: cells[3] ?? ""
    };
  }

  return undefined;
}

function replaceStatus(line, status) {
  const cells = line.split("|").slice(1, -1).map((cell) => cell.trim());
  cells[3] = status;
  return `| ${cells.join(" | ")} |`;
}

function replaceLineAt(markdown, index, nextLine) {
  const trailingNewline = markdown.endsWith("\n");
  const lines = markdown.split(/\r?\n/);
  lines[index] = nextLine;
  const joined = lines.join("\n");
  return trailingNewline && !joined.endsWith("\n") ? `${joined}\n` : joined;
}

function fail(message) {
  console.error(`promote-vm-evidence: ${message}`);
  process.exit(1);
}
