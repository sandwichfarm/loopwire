#!/usr/bin/env bash
set -euo pipefail

target=""
evidence_dir=""
require_published_release="false"
require_github_release_source="false"
release_tag=""

usage() {
  cat <<'USAGE'
Verify Loopwire VM evidence.

Usage:
  verify-vm-evidence.sh --target TARGET --evidence-dir DIR [--require-published-release]
                        [--release-tag vX.Y.Z] [--require-github-release-source]

Required files:
  pnpm-check.log
  desktop-launch.log
  desktop-binary-launch.log
  audio-host-build.log
  environment.json
  detect-audio.json
  ct-host-check.log
  autostart.log
  support-bundle.log
  support-bundle/support-bundle.json
  support-bundle/command-results.tsv
  support-bundle/notes.md
  screenshot.png
  notes.md
  command-results.tsv
  published-release-smoke.log (when --require-published-release is passed, or when present in command-results.tsv)
  published-release.json (when --release-tag is passed)

The target must exist in vm/targets.tsv. This verifier checks that the evidence bundle has the expected files and that
the backend detection JSON contains the target platform and reports array. It also checks command-results.tsv to prove
the required guest commands, including Vite desktop launch smoke and packaged desktop binary launch smoke, completed
successfully. The nested support bundle ledger must also prove its quick-profile diagnostics completed and wrote
non-empty logs. The environment manifest must match the selected VM target's distro, desktop/session, audio stack, and
architecture. With --require-published-release, the bundle must also prove an installed release smoke through
scripts/verify-published-release.sh.
With --release-tag, the bundle must include structured published-release metadata for that exact tag.
Use --require-github-release-source with --require-published-release --release-tag for final support claims that must
prove the VM installed from the GitHub Release surface instead of a guest-visible local release directory.
USAGE
}

fail() {
  echo "verify-vm-evidence: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      target="${2:-}"
      shift 2
      ;;
    --evidence-dir)
      evidence_dir="${2:-}"
      shift 2
      ;;
    --require-published-release)
      require_published_release="true"
      shift
      ;;
    --require-github-release-source)
      require_github_release_source="true"
      shift
      ;;
    --release-tag)
      release_tag="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$target" ] || fail "missing --target"
[ -n "$evidence_dir" ] || fail "missing --evidence-dir"
[ -d "$evidence_dir" ] || fail "missing evidence directory: $evidence_dir"
awk -F '\t' -v id="$target" 'NF && $1 == id { found = 1 } END { exit found ? 0 : 1 }' vm/targets.tsv \
  || fail "unknown VM target: $target"

if [ -n "$release_tag" ]; then
  [[ "$release_tag" =~ ^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
    || fail "release tag must be v-prefixed semver without path separators: $release_tag"
  [ "$require_published_release" = "true" ] || fail "--release-tag requires --require-published-release"
fi
if [ "$require_github_release_source" = "true" ]; then
  [ "$require_published_release" = "true" ] || fail "--require-github-release-source requires --require-published-release"
  [ -n "$release_tag" ] || fail "--require-github-release-source requires --release-tag"
fi

for required in \
  pnpm-check.log \
  desktop-launch.log \
  desktop-binary-launch.log \
  audio-host-build.log \
  environment.json \
  detect-audio.json \
  ct-host-check.log \
  autostart.log \
  support-bundle.log \
  support-bundle/support-bundle.json \
  support-bundle/command-results.tsv \
  support-bundle/notes.md \
  notes.md \
  command-results.tsv \
  screenshot.png; do
  [ -s "$evidence_dir/$required" ] || fail "missing or empty evidence file: $required"
done

if [ "$require_published_release" = "true" ]; then
  [ -s "$evidence_dir/published-release-smoke.log" ] || fail "missing or empty evidence file: published-release-smoke.log"
fi

if [ -n "$release_tag" ]; then
  [ -s "$evidence_dir/published-release.json" ] || fail "missing or empty evidence file: published-release.json"
fi

node -e '
const fs = require("node:fs");
const environmentPath = process.argv[1];
const target = process.argv[2];
const targetFile = process.argv[3];
const environment = JSON.parse(fs.readFileSync(environmentPath, "utf8"));
const targetRow = fs.readFileSync(targetFile, "utf8")
  .split(/\r?\n/)
  .find((line) => line && !line.trim().startsWith("#") && line.split("\t")[0] === target);

if (!targetRow) {
  throw new Error(`unknown VM target: ${target}`);
}

const [id, distro, family, desktop, session, audio, arch, tier, notes] = targetRow.split("\t");
const expected = { id, distro, family, desktop, session, audio, arch, tier, notes };

if (environment.kind !== "loopwire.vm-environment" || environment.version !== 1) {
  throw new Error("environment.json must be a loopwire.vm-environment v1 manifest");
}

for (const [key, value] of Object.entries(expected)) {
  if (environment.target?.[key] !== value) {
    throw new Error(`environment target ${key} mismatch: expected ${value}, found ${environment.target?.[key]}`);
  }
}

const observed = environment.observed ?? {};
if (observed.platform !== "linux") {
  throw new Error("environment observed platform must be linux");
}

if (observed.architecture !== arch) {
  throw new Error(`environment architecture mismatch: expected ${arch}, found ${observed.architecture}`);
}

const distroId = observed.osRelease?.id;
if (distroId !== expectedDistroId(distro)) {
  throw new Error(`environment distro mismatch: expected ${expectedDistroId(distro)}, found ${distroId || "unknown"}`);
}

if (!matchesSession(observed.sessionType, session)) {
  throw new Error(`environment session mismatch: expected ${session}, found ${observed.sessionType || "unknown"}`);
}

if (!matchesDesktop(observed.desktop, desktop)) {
  throw new Error(`environment desktop mismatch: expected ${desktop}, found ${observed.desktop || "unknown"}`);
}

function expectedDistroId(value) {
  const known = {
    "Arch Linux": "arch",
    Fedora: "fedora",
    "Ubuntu LTS": "ubuntu",
    "Debian stable": "debian",
    NixOS: "nixos",
    "openSUSE Tumbleweed": "opensuse-tumbleweed"
  };

  return known[value] ?? value.toLowerCase();
}

function matchesSession(observedValue, expectedValue) {
  return String(observedValue ?? "").toLowerCase() === expectedValue.toLowerCase();
}

function matchesDesktop(observedValue, expectedValue) {
  const observedTokens = String(observedValue ?? "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
  const aliases = {
    Hyprland: ["hyprland"],
    "KDE Plasma": ["kde", "plasma"],
    GNOME: ["gnome"],
    Xfce: ["xfce", "xfce4"],
    Sway: ["sway"]
  };

  const expectedTokens = aliases[expectedValue] ?? [expectedValue.toLowerCase()];
  return expectedTokens.some((token) => observedTokens.includes(token));
}
' "$evidence_dir/environment.json" "$target" vm/targets.tsv

node -e '
const fs = require("node:fs");
const path = process.argv[1];
const target = process.argv[2];
const targetFile = process.argv[3];
const data = JSON.parse(fs.readFileSync(path, "utf8"));
if (data.platform !== "linux") {
  throw new Error("detect-audio.json platform must be linux");
}
if (!Array.isArray(data.reports) || data.reports.length === 0) {
  throw new Error("detect-audio.json must contain backend reports");
}

const targetRow = fs.readFileSync(targetFile, "utf8")
  .split(/\r?\n/)
  .find((line) => line && !line.trim().startsWith("#") && line.split("\t")[0] === target);

if (!targetRow) {
  throw new Error(`unknown VM target: ${target}`);
}

const expectedAudio = targetRow.split("\t")[5];
const requiredBackends = requiredBackendsForAudio(expectedAudio);
const missing = requiredBackends.filter((kind) => !backendAvailable(data.reports, kind));

if (missing.length > 0) {
  throw new Error(`target audio stack ${expectedAudio} requires available backend report(s): ${missing.join(", ")}`);
}

function backendAvailable(reports, kind) {
  return reports.some((report) => report.kind === kind && report.availability === "available");
}

function requiredBackendsForAudio(value) {
  const requirements = {
    "PipeWire/WirePlumber": ["pipewire"],
    "PipeWire/PulseAudio compatibility": ["pipewire", "pulseaudio"],
    PulseAudio: ["pulseaudio"],
    JACK: ["jack"]
  };
  const required = requirements[value];
  if (!required) {
    throw new Error(`unsupported target audio stack: ${value}`);
  }

  return required;
}
' "$evidence_dir/detect-audio.json" "$target" vm/targets.tsv

node -e '
const fs = require("node:fs");
const path = process.argv[1];
const data = JSON.parse(fs.readFileSync(path, "utf8"));
if (data.kind !== "loopwire.support-bundle") {
  throw new Error("support-bundle.json kind must be loopwire.support-bundle");
}
if (data.redacted !== true) {
  throw new Error("support-bundle.json must declare redacted=true");
}
if (!Array.isArray(data.commands) || data.commands.length === 0) {
  throw new Error("support-bundle.json must contain command results");
}
if (data.audio?.status !== "parsed") {
  throw new Error("support-bundle.json must include parsed audio backend summary");
}
if (!Array.isArray(data.audio.backends) || data.audio.backends.length === 0) {
  throw new Error("support-bundle.json audio summary must contain backend rows");
}
for (const backend of data.audio.backends) {
  if (!backend.kind || !backend.availability || !backend.controlScope) {
    throw new Error("support-bundle.json audio backend rows must include kind, availability, and controlScope");
  }
  if (!Array.isArray(backend.gaps)) {
    throw new Error("support-bundle.json audio backend rows must include gaps arrays");
  }
}
' "$evidence_dir/support-bundle/support-bundle.json"

node -e '
const fs = require("node:fs");
const path = require("node:path");
const resultsPath = process.argv[1];
const supportDir = process.argv[2];
const required = new Map([
  ["detect-audio", "detect-audio.json"],
  ["ct-host-check", "ct-host-check.log"],
  ["autostart-status", "autostart-status.log"]
]);

const lines = fs.readFileSync(resultsPath, "utf8")
  .split(/\r?\n/)
  .filter(Boolean);
const header = lines.shift();
if (header !== "name\texitCode\tstartedAt\tfinishedAt\tlog") {
  throw new Error("support-bundle/command-results.tsv has an unexpected header");
}

const rows = lines.map((line, index) => {
  const cells = line.split("\t");
  if (cells.length !== 5) {
    throw new Error(`support-bundle/command-results.tsv row ${index + 2} must have 5 tab-separated columns`);
  }

  const [name, exitCode, startedAt, finishedAt, log] = cells;
  return { name, exitCode, startedAt, finishedAt, log };
});

for (const [name, expectedLog] of required) {
  const row = rows.find((candidate) => candidate.name === name);
  if (!row) {
    throw new Error(`support-bundle/command-results.tsv missing required command: ${name}`);
  }
  if (row.exitCode !== "0") {
    throw new Error(`${name} exited ${row.exitCode}; inspect support-bundle/${row.log}`);
  }
  if (row.log !== expectedLog) {
    throw new Error(`${name} expected log ${expectedLog}, found ${row.log}`);
  }
  if (!row.startedAt || !row.finishedAt) {
    throw new Error(`${name} is missing start or finish timestamp`);
  }
  if (row.log.includes("/") || row.log.includes("\\\\") || row.log === "." || row.log === "..") {
    throw new Error(`${name} support-bundle log must be a basename: ${row.log}`);
  }

  const logPath = path.join(supportDir, row.log);
  if (!fs.statSync(logPath).isFile() || fs.statSync(logPath).size === 0) {
    throw new Error(`${name} support-bundle log is missing or empty: ${row.log}`);
  }
}
' "$evidence_dir/support-bundle/command-results.tsv" "$evidence_dir/support-bundle"

node -e '
const fs = require("node:fs");
const path = require("node:path");
const resultsPath = process.argv[1];
const evidenceDir = process.argv[2];
const requirePublishedRelease = process.argv[3] === "true";
const required = new Map([
  ["pnpm-check", "pnpm-check.log"],
  ["desktop-launch", "desktop-launch.log"],
  ["desktop-binary-launch", "desktop-binary-launch.log"],
  ["audio-host-build", "audio-host-build.log"],
  ["detect-audio", "detect-audio.json"],
  ["ct-host-check", "ct-host-check.log"],
  ["autostart", "autostart.log"],
  ["support-bundle", "support-bundle.log"]
]);
const optional = new Map([
  ["published-release-smoke", "published-release-smoke.log"]
]);

if (requirePublishedRelease) {
  required.set("published-release-smoke", "published-release-smoke.log");
}

const rows = fs.readFileSync(resultsPath, "utf8")
  .split(/\r?\n/)
  .filter(Boolean)
  .map((line, index) => {
    const cells = line.split("\t");
    if (cells.length !== 5) {
      throw new Error(`command-results.tsv row ${index + 1} must have 5 tab-separated columns`);
    }

    const [name, status, startedAt, finishedAt, log] = cells;
    return { name, status, startedAt, finishedAt, log };
  });

for (const [name, expectedLog] of required) {
  validateCommand(name, expectedLog, true);
}

for (const [name, expectedLog] of optional) {
  validateCommand(name, expectedLog, false);
}

function validateCommand(name, expectedLog, requiredCommand) {
  const row = rows.find((candidate) => candidate.name === name);
  if (!row) {
    const optionalLog = path.join(evidenceDir, expectedLog);
    if (!requiredCommand && !fs.existsSync(optionalLog)) {
      return;
    }

    throw new Error(`command-results.tsv missing required command: ${name}`);
  }

  if (row.status !== "0") {
    throw new Error(`${name} exited ${row.status}; inspect ${row.log}`);
  }

  if (row.log !== expectedLog) {
    throw new Error(`${name} expected log ${expectedLog}, found ${row.log}`);
  }

  if (!row.startedAt || !row.finishedAt) {
    throw new Error(`${name} is missing start or finish timestamp`);
  }

  const logPath = path.join(evidenceDir, row.log);
  if (!fs.statSync(logPath).isFile() || fs.statSync(logPath).size === 0) {
    throw new Error(`${name} log is missing or empty: ${row.log}`);
  }
}
' "$evidence_dir/command-results.tsv" "$evidence_dir" "$require_published_release"

if [ -n "$release_tag" ]; then
  node -e '
const fs = require("node:fs");
const path = process.argv[1];
const expectedTag = process.argv[2];
const requireGithubSource = process.argv[3] === "true";
const data = JSON.parse(fs.readFileSync(path, "utf8"));

if (data.kind !== "loopwire.vm-published-release" || data.version !== 1) {
  throw new Error("published-release.json must be a loopwire.vm-published-release v1 manifest");
}

if (data.release?.tag !== expectedTag) {
  throw new Error(`published release tag mismatch: expected ${expectedTag}, found ${data.release?.tag || "unknown"}`);
}

if (!["directory", "github"].includes(data.source)) {
  throw new Error("published-release.json source must be directory or github");
}

if (requireGithubSource && data.source !== "github") {
  throw new Error("published-release.json source must be github for final release support evidence");
}

if (!data.release?.publicKey) {
  throw new Error("published-release.json must include release.publicKey");
}

if (data.source === "github" && !data.release?.repo) {
  throw new Error("published-release.json github source must include release.repo");
}

if (data.source === "directory" && !data.release?.directory) {
  throw new Error("published-release.json directory source must include release.directory");
}
' "$evidence_dir/published-release.json" "$release_tag" "$require_github_release_source"
fi

node -e '
const fs = require("node:fs");
const zlib = require("node:zlib");
const path = process.argv[1];
const data = fs.readFileSync(path);
const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
if (data.length < signature.length || !signature.every((byte, index) => data[index] === byte)) {
  throw new Error("screenshot.png must be a PNG file");
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

let offset = signature.length;
let width = 0;
let height = 0;
let bitDepth = 0;
let colorType = 0;
let sawIhdr = false;
let sawIend = false;
const idatChunks = [];

while (offset < data.length) {
  if (offset + 12 > data.length) {
    throw new Error("screenshot.png has a truncated PNG chunk header");
  }

  const length = data.readUInt32BE(offset);
  const type = data.toString("ascii", offset + 4, offset + 8);
  const chunkStart = offset + 8;
  const chunkEnd = chunkStart + length;
  const nextOffset = chunkEnd + 4;

  if (chunkEnd > data.length || nextOffset > data.length) {
    throw new Error(`screenshot.png has a truncated ${type} chunk`);
  }
  const expectedCrc = data.readUInt32BE(chunkEnd);
  const actualCrc = crc32(data.subarray(offset + 4, chunkEnd));
  if (actualCrc !== expectedCrc) {
    throw new Error(`screenshot.png has an invalid ${type} chunk CRC`);
  }

  if (!sawIhdr && type !== "IHDR") {
    throw new Error("screenshot.png must start with a valid PNG IHDR chunk");
  }

  if (type === "IHDR") {
    if (sawIhdr || length !== 13) {
      throw new Error("screenshot.png must contain exactly one valid PNG IHDR chunk");
    }
    width = data.readUInt32BE(chunkStart);
    height = data.readUInt32BE(chunkStart + 4);
    bitDepth = data[chunkStart + 8];
    colorType = data[chunkStart + 9];
    const compression = data[chunkStart + 10];
    const filter = data[chunkStart + 11];
    const interlace = data[chunkStart + 12];
    if (compression !== 0 || filter !== 0 || interlace !== 0) {
      throw new Error("screenshot.png must be a non-interlaced PNG with standard compression and filtering");
    }
    sawIhdr = true;
  } else if (type === "IDAT") {
    idatChunks.push(data.subarray(chunkStart, chunkEnd));
  } else if (type === "IEND") {
    if (length !== 0) {
      throw new Error("screenshot.png IEND chunk must be empty");
    }
    sawIend = true;
    break;
  }

  offset = nextOffset;
}

if (!sawIhdr || !sawIend) {
  throw new Error("screenshot.png must contain IHDR and IEND chunks");
}
if (width < 320 || height < 200) {
  throw new Error(`screenshot.png is too small for desktop evidence: ${width}x${height}`);
}
if (idatChunks.length === 0) {
  throw new Error("screenshot.png must contain PNG image data");
}

const channelsByColorType = new Map([
  [0, 1],
  [2, 3],
  [3, 1],
  [4, 2],
  [6, 4]
]);
const channels = channelsByColorType.get(colorType);
if (!channels) {
  throw new Error(`screenshot.png has unsupported PNG color type: ${colorType}`);
}
const validBitDepths = new Set([1, 2, 4, 8, 16]);
if (!validBitDepths.has(bitDepth)) {
  throw new Error(`screenshot.png has unsupported PNG bit depth: ${bitDepth}`);
}

const inflated = zlib.inflateSync(Buffer.concat(idatChunks));
const rowBytes = 1 + Math.ceil((width * channels * bitDepth) / 8);
const expectedBytes = rowBytes * height;
if (inflated.length !== expectedBytes) {
  throw new Error(`screenshot.png image data has ${inflated.length} decoded bytes; expected ${expectedBytes}`);
}
' "$evidence_dir/screenshot.png"

echo "VM evidence verification passed for $target."
