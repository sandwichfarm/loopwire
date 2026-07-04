#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${LOOPWIRE_VM_TARGETS:-$root/vm/targets.tsv}"

target=""
output_dir=""
screenshot_file=""
screenshot_command=""
desktop_port="5181"
operator_note=""
published_release_dir=""
published_release_repo=""
published_release_tag=""
release_public_key=""
require_published_release="false"
require_github_release_source="false"
failed=0
last_status=0

usage() {
  cat <<'USAGE'
Collect Loopwire guest VM evidence.

Usage:
  collect-vm-evidence.sh --target TARGET --output-dir DIR [options]

Options:
  --screenshot-file FILE       Copy an already captured screenshot to screenshot.png.
  --screenshot-command CMD     Run CMD with LOOPWIRE_SCREENSHOT_PATH set to screenshot.png.
  --desktop-port PORT          Local port for the desktop launch smoke. Defaults to 5181.
  --published-release-dir DIR  Run installed-release smoke against a signed local release directory.
  --published-release-repo REPO Run installed-release smoke against a GitHub release repository.
  --published-release-tag TAG  Release tag for installed-release smoke.
  --release-public-key FILE    Public key for published-release signature verification.
  --require-published-release  Require published-release smoke arguments and fail if they are absent.
  --require-github-release-source
                              Require installed-release smoke to use --published-release-repo.
  --note TEXT                  Append operator context to notes.md.

The script runs inside a guest VM from a checked-out Loopwire repository. It writes the files expected by
verify-vm-evidence.sh and fails closed if command output or screenshot evidence is missing.
USAGE
}

fail() {
  echo "collect-vm-evidence: $*" >&2
  exit 1
}

validate_tcp_port() {
  port="$1"
  label="$2"

  case "$port" in
    "" | *[!0-9]*)
      fail "$label must be a number from 1 to 65535"
      ;;
  esac

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    fail "$label must be a number from 1 to 65535"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      target="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --screenshot-file)
      screenshot_file="${2:-}"
      shift 2
      ;;
    --screenshot-command)
      screenshot_command="${2:-}"
      shift 2
      ;;
    --desktop-port)
      desktop_port="${2:-}"
      shift 2
      ;;
    --published-release-dir)
      published_release_dir="${2:-}"
      shift 2
      ;;
    --published-release-repo)
      published_release_repo="${2:-}"
      shift 2
      ;;
    --published-release-tag)
      published_release_tag="${2:-}"
      shift 2
      ;;
    --release-public-key)
      release_public_key="${2:-}"
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
    --note)
      operator_note="${2:-}"
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
[ -n "$output_dir" ] || fail "missing --output-dir"
[ -f "$target_file" ] || fail "missing target file: $target_file"
validate_tcp_port "$desktop_port" "--desktop-port"

if [ -n "$published_release_dir" ] && [ -n "$published_release_repo" ]; then
  fail "use either --published-release-dir or --published-release-repo, not both"
fi

if [ -n "$published_release_tag" ] && [ -z "$published_release_dir" ] && [ -z "$published_release_repo" ]; then
  fail "--published-release-tag requires --published-release-dir or --published-release-repo"
fi

if [ "$require_published_release" = "true" ] && [ -z "$published_release_dir" ] && [ -z "$published_release_repo" ]; then
  fail "--require-published-release requires --published-release-dir or --published-release-repo"
fi

if [ "$require_github_release_source" = "true" ]; then
  [ "$require_published_release" = "true" ] || fail "--require-github-release-source requires --require-published-release"
  [ -n "$published_release_repo" ] || fail "--require-github-release-source requires --published-release-repo"
  [ -z "$published_release_dir" ] || fail "--require-github-release-source cannot be used with --published-release-dir"
fi

if [ -n "$published_release_dir" ] || [ -n "$published_release_repo" ]; then
  [ -n "$release_public_key" ] || fail "published release smoke requires --release-public-key"
  if [ -z "$published_release_tag" ]; then
    fail "published release smoke requires --published-release-tag"
  fi
fi

target_row="$(awk -F '\t' -v id="$target" '$1 == id { print; found = 1 } END { if (!found) exit 1 }' "$target_file")" ||
  fail "unknown VM target: $target"

mkdir -p "$output_dir"
: >"$output_dir/command-results.tsv"

write_notes() {
  {
    echo "# Loopwire VM Evidence Notes"
    echo
    echo "- Target: $target"
    echo "- Generated: $(date --iso-8601=seconds)"
    echo "- Repository: $(git remote get-url origin 2>/dev/null || echo unknown)"
    echo "- Commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "- Matrix row: $target_row"
    echo "- Kernel: $(uname -srmo)"
    echo "- Session type: ${XDG_SESSION_TYPE:-unknown}"
    echo "- Desktop: ${XDG_CURRENT_DESKTOP:-unknown}"
    echo "- Wayland display: ${WAYLAND_DISPLAY:-none}"
    echo "- X11 display: ${DISPLAY:-none}"
    echo
    echo "## OS Release"
    if [ -f /etc/os-release ]; then
      sed -n '1,20p' /etc/os-release
    else
      echo "Unavailable."
    fi
    if [ -n "$operator_note" ]; then
      echo
      echo "## Operator Note"
      echo "$operator_note"
    fi
  } >"$output_dir/notes.md"
}

write_environment_manifest() {
  node - "$target_file" "$target" "$output_dir/environment.json" <<'NODE'
const fs = require("node:fs");
const os = require("node:os");

const [targetFile, targetId, outputPath] = process.argv.slice(2);
const row = fs.readFileSync(targetFile, "utf8")
  .split(/\r?\n/)
  .find((line) => line && !line.trim().startsWith("#") && line.split("\t")[0] === targetId);

if (!row) {
  throw new Error(`unknown VM target: ${targetId}`);
}

const [id, distro, family, desktop, session, audio, arch, tier, notes] = row.split("\t");

const manifest = {
  kind: "loopwire.vm-environment",
  version: 1,
  generatedAt: new Date().toISOString(),
  target: { id, distro, family, desktop, session, audio, arch, tier, notes },
  observed: {
    platform: process.platform,
    architecture: normalizeArch(os.arch()),
    kernel: `${os.type()} ${os.release()} ${os.machine()}`,
    osRelease: readOsRelease(),
    sessionType: process.env.LOOPWIRE_EVIDENCE_SESSION || process.env.XDG_SESSION_TYPE || "unknown",
    desktop: process.env.LOOPWIRE_EVIDENCE_DESKTOP || process.env.XDG_CURRENT_DESKTOP || "unknown",
    hasWaylandDisplay: Boolean(process.env.WAYLAND_DISPLAY),
    hasX11Display: Boolean(process.env.DISPLAY)
  }
};

fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);

function readOsRelease() {
  if (!fs.existsSync("/etc/os-release")) {
    return {};
  }

  const pairs = {};
  for (const line of fs.readFileSync("/etc/os-release", "utf8").split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match) {
      continue;
    }

    pairs[match[1].toLowerCase()] = match[2].replace(/^"|"$/g, "");
  }

  return pairs;
}

function normalizeArch(value) {
  if (value === "x64") {
    return "x86_64";
  }

  if (value === "arm64") {
    return "aarch64";
  }

  return value;
}
NODE
}

record_result() {
  local name="$1"
  local log="$2"
  local status="$3"
  local started_at="$4"
  local finished_at="$5"

  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$started_at" "$finished_at" "$log" \
    >>"$output_dir/command-results.tsv"
}

run_logged() {
  local name="$1"
  local log="$2"
  shift 2
  local started_at
  local finished_at
  local status

  started_at="$(date --iso-8601=seconds)"
  if "$@" >"$output_dir/$log" 2>&1; then
    status=0
  else
    status=$?
    failed=1
  fi
  last_status="$status"
  finished_at="$(date --iso-8601=seconds)"
  record_result "$name" "$log" "$status" "$started_at" "$finished_at"
}

run_audio_detect() {
  run_logged "audio-host-build" "audio-host-build.log" pnpm --filter @loopwire/audio-host build
  if [ "$last_status" -eq 0 ]; then
    run_logged "detect-audio" "detect-audio.json" node scripts/detect-audio-backends.mjs --pretty
  else
    : >"$output_dir/detect-audio.json"
  fi
}

run_desktop_launch_smoke() {
  local log="$output_dir/desktop-launch.log"
  local started_at
  local finished_at
  local status=1
  local desktop_url="http://127.0.0.1:${desktop_port}/"
  local launch_pid=""

  started_at="$(date --iso-8601=seconds)"
  : >"$log"

  pnpm --filter @loopwire/desktop exec vite --host 127.0.0.1 --port "$desktop_port" --strictPort >>"$log" 2>&1 &
  launch_pid="$!"

  for _attempt in $(seq 1 60); do
    if ! kill -0 "$launch_pid" >/dev/null 2>&1; then
      wait "$launch_pid" || true
      echo "Loopwire desktop launch process exited before readiness." >>"$log"
      break
    fi

    if node - "$desktop_url" >>"$log" 2>&1 <<'NODE'; then
const url = process.argv[2];

(async () => {
  const response = await fetch(url);
  const body = await response.text();

  if (!response.ok) {
    throw new Error(`Desktop launch returned HTTP ${response.status}`);
  }

  if (!body.includes("<title>Loopwire</title>") || !body.includes('id="app"')) {
    throw new Error("Desktop launch response did not look like the Loopwire shell.");
  }
})().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
NODE
      status=0
      echo "Loopwire desktop launch smoke passed: $desktop_url" >>"$log"
      break
    fi

    sleep 0.5
  done

  if kill -0 "$launch_pid" >/dev/null 2>&1; then
    kill "$launch_pid" >/dev/null 2>&1 || true
    wait "$launch_pid" >/dev/null 2>&1 || true
  fi

  if [ "$status" -ne 0 ]; then
    failed=1
  fi

  last_status="$status"
  finished_at="$(date --iso-8601=seconds)"
  record_result "desktop-launch" "desktop-launch.log" "$status" "$started_at" "$finished_at"
}

run_support_bundle() {
  run_logged "support-bundle" "support-bundle.log" node scripts/collect-support-bundle.mjs \
    --output-dir "$output_dir/support-bundle" \
    --profile quick
}

run_published_release_smoke() {
  if [ -z "$published_release_dir" ] && [ -z "$published_release_repo" ]; then
    return 0
  fi

  write_published_release_manifest

  if [ -n "$published_release_dir" ]; then
    run_logged "published-release-smoke" "published-release-smoke.log" \
      bash scripts/verify-published-release.sh \
      --release-dir "$published_release_dir" \
      --tag "$published_release_tag" \
      --public-key "$release_public_key"
    return 0
  fi

  run_logged "published-release-smoke" "published-release-smoke.log" \
    bash scripts/verify-published-release.sh \
    --repo "$published_release_repo" \
    --tag "$published_release_tag" \
    --public-key "$release_public_key"
}

write_published_release_manifest() {
  node - "$output_dir/published-release.json" "$published_release_dir" "$published_release_repo" \
    "$published_release_tag" "$release_public_key" <<'NODE'
const fs = require("node:fs");

const [outputPath, releaseDir, releaseRepo, releaseTag, releasePublicKey] = process.argv.slice(2);
const source = releaseDir ? "directory" : "github";
const manifest = {
  kind: "loopwire.vm-published-release",
  version: 1,
  generatedAt: new Date().toISOString(),
  source,
  release: {
    tag: releaseTag,
    publicKey: releasePublicKey
  }
};

if (releaseDir) {
  manifest.release.directory = releaseDir;
}

if (releaseRepo) {
  manifest.release.repo = releaseRepo;
}

fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
}

capture_screenshot() {
  local screenshot_path="$output_dir/screenshot.png"
  rm -f "$screenshot_path"

  if [ -n "$screenshot_file" ]; then
    [ -s "$screenshot_file" ] || fail "missing screenshot file: $screenshot_file"
    cp "$screenshot_file" "$screenshot_path"
  elif [ -n "$screenshot_command" ]; then
    if ! LOOPWIRE_SCREENSHOT_PATH="$screenshot_path" bash -lc "$screenshot_command"; then
      echo "Screenshot command failed." >"$output_dir/screenshot.log"
      failed=1
      return 0
    fi
  elif command -v grim >/dev/null 2>&1; then
    if ! grim "$screenshot_path"; then
      echo "grim failed to capture screenshot." >"$output_dir/screenshot.log"
      failed=1
      return 0
    fi
  elif command -v gnome-screenshot >/dev/null 2>&1; then
    if ! gnome-screenshot -f "$screenshot_path"; then
      echo "gnome-screenshot failed to capture screenshot." >"$output_dir/screenshot.log"
      failed=1
      return 0
    fi
  elif command -v spectacle >/dev/null 2>&1; then
    if ! spectacle -b -n -o "$screenshot_path"; then
      echo "spectacle failed to capture screenshot." >"$output_dir/screenshot.log"
      failed=1
      return 0
    fi
  else
    echo "No supported screenshot tool found. Pass --screenshot-file or --screenshot-command." \
      >"$output_dir/screenshot.log"
    failed=1
    return 0
  fi

  if [ ! -s "$screenshot_path" ]; then
    echo "Screenshot command did not create a non-empty screenshot.png." >"$output_dir/screenshot.log"
    failed=1
  fi
}

write_notes
write_environment_manifest
run_logged "pnpm-check" "pnpm-check.log" pnpm check
run_desktop_launch_smoke
run_audio_detect
run_logged "ct-host-check" "ct-host-check.log" bash scripts/ct-host-check.sh
run_logged "autostart" "autostart.log" pnpm verify:autostart
run_support_bundle
run_published_release_smoke
capture_screenshot

verify_args=(--target "$target" --evidence-dir "$output_dir")
if [ "$require_published_release" = "true" ]; then
  verify_args+=(--require-published-release)
fi
if [ -n "$published_release_tag" ]; then
  verify_args+=(--release-tag "$published_release_tag")
fi
if [ "$require_github_release_source" = "true" ]; then
  verify_args+=(--require-github-release-source)
fi

if bash scripts/verify-vm-evidence.sh "${verify_args[@]}" >"$output_dir/vm-evidence-verify.log" 2>&1; then
  record_result "verify-vm-evidence" "vm-evidence-verify.log" 0 "$(date --iso-8601=seconds)" \
    "$(date --iso-8601=seconds)"
else
  failed=1
  record_result "verify-vm-evidence" "vm-evidence-verify.log" 1 "$(date --iso-8601=seconds)" \
    "$(date --iso-8601=seconds)"
fi

if [ "$failed" -ne 0 ]; then
  echo "VM evidence collection failed; inspect $output_dir." >&2
  exit 1
fi

echo "VM evidence collected under $output_dir."
