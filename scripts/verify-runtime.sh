#!/usr/bin/env bash
set -euo pipefail

pnpm verify:autostart
pnpm verify:install
pnpm verify:release
pnpm verify:packaging
pnpm verify:vm
pnpm verify:docs
