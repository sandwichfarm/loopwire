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
 * Usage: node scripts/e2e-desktop-shell.mjs [--binary PATH] [--port N] [--dsp-provider-smoke]
 */
import { spawn, spawnSync } from "node:child_process";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const port = Number(readOption("--port") ?? "4444");
const nativePort = port + 1;
const binary = resolve(readOption("--binary") ?? "apps/desktop/src-tauri/target/release/loopwire");
const dspProviderSmoke = args.includes("--dsp-provider-smoke");
const keepTemp = args.includes("--keep-temp");
const base = `http://127.0.0.1:${port}`;
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

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

function runChecked(command, commandArgs, options = {}) {
  const result = spawnSync(command, commandArgs, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    fail(`${command} ${commandArgs.join(" ")} failed`);
  }
}

async function prepareDspProviderSmoke() {
  runChecked("pnpm", ["--filter", "@loopwire/core", "build"]);
  runChecked("pnpm", ["--filter", "@loopwire/audio-host", "build"]);

  const root = await mkdtemp(join(tmpdir(), "loopwire-e2e-shell-"));
  const configHome = join(root, "config");
  const stateHome = join(root, "state");
  const providerStore = join(root, "provider-store");
  const stateFile = join(configHome, "loopwire", "state.json");
  const providerCli = join(repoRoot, "packages/audio-host/dist/dsp-provider-cli.js");
  const providerCommand = join(root, "loopwire-dsp-provider-live-smoke");

  if (!existsSync(providerCli)) {
    fail(`DSP provider CLI not found at ${providerCli}`);
  }

  await mkdir(dirname(stateFile), { recursive: true });
  await mkdir(providerStore, { recursive: true });

  const core = await import(new URL("../packages/core/dist/index.js", import.meta.url));
  const now = "2026-07-08T00:00:00.000Z";
  const state = core.setSelectedBackend(core.createDefaultState(now), "dsp");
  await writeFile(stateFile, core.serializeState(state), "utf8");
  await writeFile(
    providerCommand,
    `#!/usr/bin/env sh
export LOOPWIRE_DSP_PROVIDER_DIR=${shellQuote(providerStore)}
export LOOPWIRE_DSP_PROVIDER_LIVE_SMOKE=1
exec node ${shellQuote(providerCli)} "$@"
`,
    "utf8"
  );
  await chmod(providerCommand, 0o755);

  const providerEnv = {
    ...process.env,
    LOOPWIRE_DSP_PROVIDER_DIR: providerStore,
    LOOPWIRE_DSP_PROVIDER_LIVE_SMOKE: "1"
  };
  for (const sourceId of ["mic", "browser"]) {
    runChecked(
      providerCommand,
      ["seed-source", "--source-id", sourceId, "--channels", "2", "--frames", "16", "--value", sourceId === "mic" ? "1" : "0.25"],
      { env: providerEnv }
    );
  }

  return {
    root,
    providerCommand,
    providerStore,
    outputFile: join(providerStore, "outputs", "studio", "recorder.json"),
    env: {
      ...providerEnv,
      XDG_CONFIG_HOME: configHome,
      XDG_STATE_HOME: stateHome
    }
  };
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

async function runDspProviderShellSmoke(sessionId, smoke) {
  await webdriver("POST", `/session/${sessionId}/execute/sync`, {
    script: `
      localStorage.setItem("loopwire.dsp-restore.v1", JSON.stringify({
        command: arguments[0],
        mode: "live",
        timeoutMs: "5000",
        frameCount: "16"
      }));
      location.reload();
      return true;
    `,
    args: [smoke.providerCommand]
  });

  let output;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (existsSync(smoke.outputFile)) {
      try {
        output = JSON.parse(readFileSync(smoke.outputFile, "utf8"));
        break;
      } catch {
        // The provider may have created the file before the JSON write is fully visible.
      }
    }
    await delay(200);
  }

  if (!output) {
    const body = await webdriver("POST", `/session/${sessionId}/execute/sync`, {
      script: "return document.body?.innerText || ''",
      args: []
    }).catch(() => "");
    throw new Error(
      `DSP provider smoke did not write ${smoke.outputFile}${body ? `; shell text: ${body.slice(0, 500)}` : ""}`
    );
  }

  if (output.configurationId !== "studio" || output.outputId !== "recorder" || !Array.isArray(output.channels)) {
    throw new Error(`DSP provider output is malformed: ${JSON.stringify(output)}`);
  }

  return output;
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

  const smoke = dspProviderSmoke ? await prepareDspProviderSmoke() : undefined;
  const driver = spawn(findTauriDriver(), ["--port", String(port), "--native-port", String(nativePort)], {
    env: smoke?.env ?? process.env,
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

    if (smoke) {
      const output = await runDspProviderShellSmoke(sessionId, smoke);
      results.push([`DSP provider live-smoke wrote ${output.outputId} in isolated temp store`, "pass"]);
    }

  } finally {
    if (sessionId) {
      await webdriver("DELETE", `/session/${sessionId}`).catch(() => {});
    }
    driver.kill("SIGTERM");
    if (smoke && !keepTemp) {
      await rm(smoke.root, { recursive: true, force: true });
    } else if (smoke) {
      console.error(`e2e-desktop-shell: kept temp proof directory: ${smoke.root}`);
    }
  }

  for (const [name, status] of results) {
    console.log(`${name}: ${status}`);
  }
  console.log(
    dspProviderSmoke
      ? "e2e-desktop-shell: smoke passed (real shell + isolated DSP provider live-smoke)"
      : "e2e-desktop-shell: smoke passed (read-only; interactive flows covered by e2e-desktop-ui.mjs)"
  );
}

await main();
