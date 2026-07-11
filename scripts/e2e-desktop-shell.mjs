#!/usr/bin/env node
/**
 * Real-shell WebDriver smoke (SEED-001 / E2E-01).
 *
 * Drives the built Tauri binary through tauri-driver + WebKitWebDriver:
 * launches the real WebKitGTK window, asserts the window title, that the
 * Tauri bridge is live, and that the app shell DOM rendered. Then closes
 * the session.
 *
 * Host requirements (manual validation surface, NOT part of `pnpm check`):
 *   - /usr/bin/WebKitWebDriver (distro webkit2gtk package).
 *   - tauri-driver on PATH or ~/.cargo/bin (`cargo install tauri-driver --locked`).
 *   - A display session (WAYLAND_DISPLAY or DISPLAY) — WebKitGTK cannot run
 *     without a compositor; this opens a real window briefly.
 *   - A built binary: `pnpm --filter @loopwire/desktop tauri:build`
 *     (default path apps/desktop/src-tauri/target/release/loopwire; override
 *     with --binary PATH).
 *
 * Deliberately read-only: it does NOT create/delete devices, because the real
 * shell applies configuration to the live PipeWire graph and mutates the
 * user's persisted app state. Interactive flow coverage (create, cable,
 * toggle, delete, reorder, persistence) lives in scripts/e2e-desktop-ui.mjs
 * against the browser preview, which is side-effect free.
 *
 * Usage: node scripts/e2e-desktop-shell.mjs [--binary PATH] [--port N]
 */
import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const args = process.argv.slice(2);
const port = Number(readOption("--port") ?? "4444");
const nativePort = port + 1;
const binary = resolve(readOption("--binary") ?? "apps/desktop/src-tauri/target/release/loopwire");
const base = `http://127.0.0.1:${port}`;

function readOption(name) {
  const index = args.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    fail(`Missing value for ${name}`);
  }
  return value;
}

function fail(message) {
  console.error(`e2e-desktop-shell: ${message}`);
  process.exit(1);
}

function findTauriDriver() {
  const onPath = spawnSync("sh", ["-c", "command -v tauri-driver || true"], { encoding: "utf8" }).stdout.trim();
  if (onPath) {
    return onPath;
  }
  const cargoBin = join(homedir(), ".cargo/bin/tauri-driver");
  return existsSync(cargoBin) ? cargoBin : undefined;
}

function delay(ms) {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, ms));
}

async function webdriver(method, path, body) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`${method} ${path} failed: ${JSON.stringify(payload.value ?? payload)}`);
  }
  return payload.value;
}

async function main() {
  const preconditions = [
    ["WebKitWebDriver", spawnSync("sh", ["-c", "command -v WebKitWebDriver || true"], { encoding: "utf8" }).stdout.trim()],
    ["tauri-driver", findTauriDriver()],
    ["display session", process.env.WAYLAND_DISPLAY || process.env.DISPLAY]
  ];
  for (const [name, present] of preconditions) {
    if (!present) {
      fail(`${name} unavailable on this host — see the header of this script for setup. Refusing to fake the smoke.`);
    }
  }
  if (!existsSync(binary)) {
    fail(`binary not found at ${binary} — build it with: pnpm --filter @loopwire/desktop tauri:build`);
  }

  const driver = spawn(findTauriDriver(), ["--port", String(port), "--native-port", String(nativePort)], {
    stdio: ["ignore", "pipe", "pipe"]
  });
  let sessionId;
  const results = [];

  try {
    // Wait for tauri-driver to accept connections.
    let ready = false;
    for (let attempt = 0; attempt < 50 && !ready; attempt += 1) {
      try {
        await fetch(`${base}/status`);
        ready = true;
      } catch {
        await delay(200);
      }
    }
    if (!ready) {
      throw new Error(`tauri-driver did not start on port ${port} (is the port free? this script never kills listeners)`);
    }

    const session = await webdriver("POST", "/session", {
      capabilities: { alwaysMatch: { "tauri:options": { application: binary } } }
    });
    sessionId = session.sessionId;

    const title = await webdriver("GET", `/session/${sessionId}/title`);
    if (!/loopwire/i.test(title)) {
      throw new Error(`unexpected window title: ${JSON.stringify(title)}`);
    }
    results.push(["window title is Loopwire", "pass"]);

    const bridge = await webdriver("POST", `/session/${sessionId}/execute/sync`, {
      script: "return typeof window.__TAURI_INTERNALS__ !== 'undefined'",
      args: []
    });
    if (bridge !== true) {
      throw new Error("Tauri bridge missing — this is not the real shell");
    }
    results.push(["Tauri bridge is live (real shell, not preview)", "pass"]);

    const shellRendered = await webdriver("POST", `/session/${sessionId}/execute/sync`, {
      script:
        "const button = [...document.querySelectorAll('button')].find((b) => b.textContent.includes('New Virtual Device'));" +
        "return Boolean(button && document.querySelector('.sidebar, [aria-label=\"Virtual audio devices\"], main'));",
      args: []
    });
    if (shellRendered !== true) {
      throw new Error("app shell DOM did not render (New Virtual Device button missing)");
    }
    results.push(["app shell DOM rendered", "pass"]);
  } finally {
    if (sessionId) {
      await webdriver("DELETE", `/session/${sessionId}`).catch(() => {});
    }
    driver.kill("SIGTERM");
  }

  for (const [name, status] of results) {
    console.log(`${name}: ${status}`);
  }
  console.log("e2e-desktop-shell: smoke passed (read-only; interactive flows covered by e2e-desktop-ui.mjs)");
}

await main();
