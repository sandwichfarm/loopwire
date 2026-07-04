#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const args = process.argv.slice(2);
const target = readOption("--target");
const allTargets = args.includes("--all");
const evidenceRoot = readOption("--evidence-root") ?? join(root, ".vm/evidence");
const evidenceDir = readOption("--evidence-dir") ?? (target ? join(evidenceRoot, target) : "");
const matrixPath = readOption("--matrix") ?? join(root, "apps/docs/docs/guide/support-matrix.md");
const dryRun = args.includes("--dry-run");
const requirePublishedRelease = args.includes("--require-published-release");
const releaseTag = readOption("--release-tag");

if (args.includes("-h") || args.includes("--help")) {
  usage();
  process.exit(0);
}

validateArgs();

if (!existsSync(matrixPath)) {
  fail(`missing support matrix: ${matrixPath}`);
}

if (allTargets) {
  promoteAllTargets();
} else {
  promoteSingleTarget();
}

function usage() {
  console.log(`Promote a Loopwire VM support-matrix row after evidence verification.

Usage:
  promote-vm-evidence.mjs --target TARGET [--evidence-dir DIR] [--evidence-root DIR] [--matrix FILE] [--dry-run]
  promote-vm-evidence.mjs --target TARGET --require-published-release --release-tag vX.Y.Z [--dry-run]
  promote-vm-evidence.mjs --all [--evidence-root DIR] [--matrix FILE] [--require-published-release] [--release-tag vX.Y.Z] [--dry-run]

The tool runs scripts/verify-vm-evidence.sh first. It only promotes rows from Manual VM to Verified.
With --all, missing evidence directories are reported and skipped; invalid evidence fails the command.
Use --require-published-release with --release-tag for final release support claims that must prove installed-release
smoke for the exact release.
Use --dry-run to verify evidence and preview the change without editing docs.
`);
}

function readOption(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function validateArgs() {
  const valueOptions = new Set(["--target", "--evidence-dir", "--evidence-root", "--matrix", "--release-tag"]);
  const flagOptions = new Set(["--all", "--dry-run", "--require-published-release"]);

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

  if (allTargets && target) {
    fail("use either --target or --all, not both");
  }

  if (!allTargets && !target) {
    fail("missing --target TARGET or --all");
  }

  if (allTargets && args.includes("--evidence-dir")) {
    fail("--all uses --evidence-root; do not pass --evidence-dir");
  }

  if (releaseTag) {
    if (!requirePublishedRelease) {
      fail("--release-tag requires --require-published-release");
    }

    if (!/^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$/.test(releaseTag)) {
      fail(`release tag must be v-prefixed semver without path separators: ${releaseTag}`);
    }
  }
}

function promoteSingleTarget() {
  if (!knownTarget(target)) {
    fail(`unknown VM target: ${target}`);
  }

  if (!existsSync(evidenceDir)) {
    fail(`missing evidence directory: ${evidenceDir}`);
  }

  verifyEvidence(target, evidenceDir);

  const matrix = readFileSync(matrixPath, "utf8");
  const promotion = promotionForTarget(matrix, target, evidenceDir);

  if (promotion.action === "already") {
    console.log(`Support matrix already marks ${target} as Verified.`);
    return;
  }

  if (dryRun) {
    console.log(`would promote ${target} from Manual VM to Verified in ${matrixPath}`);
    console.log(`evidence verified: ${evidenceDir}`);
    return;
  }

  writeFileSync(matrixPath, replaceLineAt(matrix, promotion.row.index, promotion.nextLine));
  console.log(`Promoted ${target} to Verified in ${matrixPath}.`);
}

function promoteAllTargets() {
  let matrix = readFileSync(matrixPath, "utf8");
  const promotions = [];
  const missing = [];
  let alreadyVerified = 0;

  for (const targetId of targetIds()) {
    const dir = join(evidenceRoot, targetId);
    if (!existsSync(dir)) {
      missing.push(targetId);
      continue;
    }

    verifyEvidence(targetId, dir);

    const promotion = promotionForTarget(matrix, targetId, dir);
    if (promotion.action === "already") {
      alreadyVerified += 1;
      continue;
    }

    promotions.push({ ...promotion, targetId, evidenceDir: dir });
    matrix = replaceLineAt(matrix, promotion.row.index, promotion.nextLine);
  }

  for (const targetId of missing) {
    console.log(`missing evidence: ${targetId}`);
  }

  if (promotions.length === 0) {
    console.log(`No support-matrix rows need promotion in ${matrixPath}.`);
    console.log(`Already verified: ${alreadyVerified}. Missing evidence: ${missing.length}.`);
    return;
  }

  if (dryRun) {
    for (const promotion of promotions) {
      console.log(`would promote ${promotion.targetId} from Manual VM to Verified in ${matrixPath}`);
      console.log(`evidence verified: ${promotion.evidenceDir}`);
    }
    console.log(`Dry run complete. ${promotions.length} row(s) would be promoted.`);
    return;
  }

  writeFileSync(matrixPath, matrix);
  console.log(`Promoted ${promotions.length} support-matrix row(s) in ${matrixPath}.`);
}

function promotionForTarget(markdown, id, dir) {
  const row = findTargetRow(markdown, id);

  if (!row) {
    fail(`support matrix has no row for target: ${id}`);
  }

  if (row.status === "Verified") {
    return { action: "already", row };
  }

  if (row.status !== "Manual VM") {
    fail(`cannot promote ${id} from unsupported status: ${row.status}`);
  }

  return {
    action: "promote",
    evidenceDir: dir,
    row,
    nextLine: replaceStatus(row.line, "Verified")
  };
}

function knownTarget(id) {
  return targetIds().includes(id);
}

function targetIds() {
  const targetFile = join(root, "vm/targets.tsv");
  return readFileSync(targetFile, "utf8")
    .split(/\r?\n/)
    .filter((line) => line && !line.trim().startsWith("#"))
    .map((line) => line.split("\t")[0]);
}

function verifyEvidence(id, dir) {
  const verifierArgs = ["scripts/verify-vm-evidence.sh", "--target", id, "--evidence-dir", dir];
  if (requirePublishedRelease) {
    verifierArgs.push("--require-published-release");
  }
  if (releaseTag) {
    verifierArgs.push("--release-tag", releaseTag);
  }

  const result = spawnSync(
    "bash",
    verifierArgs,
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
