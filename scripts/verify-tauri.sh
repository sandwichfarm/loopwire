#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/apps/desktop/src-tauri/Cargo.toml"

cargo fmt --manifest-path "$manifest" -- --check
cargo check --manifest-path "$manifest"
cargo test --manifest-path "$manifest"
