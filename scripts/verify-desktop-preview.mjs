#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const args = process.argv.slice(2);

if (args.includes("--help")) {
  console.log(`Usage:
  verify-desktop-preview.mjs [--chromium-bin PATH] [--screenshot-dir DIR] [--skip-if-missing]

Builds the desktop app, starts Vite preview, drives a system Chromium through the Chrome DevTools Protocol, captures
desktop and mobile screenshots, and verifies the hidden-monitor recovery tray has no horizontal overflow.

Options:
  --chromium-bin PATH    Chromium/Chrome executable. Defaults to CHROMIUM_BIN or PATH lookup.
  --screenshot-dir DIR   Directory for PNG screenshots. Defaults to a temporary directory.
  --skip-if-missing      Exit 0 when Chromium is unavailable.
`);
  process.exit(0);
}

async function main() {
  const chromiumBin = readOption("--chromium-bin") ?? process.env.CHROMIUM_BIN ?? findChromium();
  const screenshotDir = resolve(readOption("--screenshot-dir") ?? mkdtempSync(join(tmpdir(), "loopwire-preview-")));
  const skipIfMissing = args.includes("--skip-if-missing");

  if (!chromiumBin) {
    if (skipIfMissing) {
      console.log("desktop preview smoke skipped: Chromium executable not found");
      return;
    }
    fail("Chromium executable not found. Pass --chromium-bin PATH or --skip-if-missing.");
  }

  mkdirSync(screenshotDir, { recursive: true });

  const previewPort = await freePort();
  const cdpPort = await freePort();
  const userDataDir = mkdtempSync(join(tmpdir(), "loopwire-chromium-"));
  const children = [];

  try {
    run("pnpm", ["--filter", "@loopwire/desktop", "build"]);
    const preview = spawn("pnpm", [
      "exec",
      "vite",
      "preview",
      "--host",
      "127.0.0.1",
      "--port",
      String(previewPort)
    ], {
      cwd: resolve("apps/desktop"),
      stdio: ["ignore", "pipe", "pipe"]
    });
    children.push(preview);
    await waitForHttp(`http://127.0.0.1:${previewPort}/`);

    const chromium = spawn(chromiumBin, [
      "--headless=new",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--no-sandbox",
      `--remote-debugging-port=${cdpPort}`,
      `--user-data-dir=${userDataDir}`,
      "about:blank"
    ], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    children.push(chromium);

    const wsUrl = await waitForCdp(cdpPort);
    const cdp = await CdpClient.connect(wsUrl);
    const url = `http://127.0.0.1:${previewPort}/`;
    const results = [];

    results.push(await verifyViewport(cdp, url, { width: 1440, height: 900 }, "desktop", screenshotDir));
    results.push(await verifyViewport(cdp, url, { width: 390, height: 844 }, "mobile", screenshotDir));
    await cdp.close();

    for (const result of results) {
      console.log(JSON.stringify(result));
    }
  } finally {
    for (const child of children.toReversed()) {
      await terminateChild(child);
    }
    await removeWithRetries(userDataDir);
  }
}

async function verifyViewport(cdp, url, viewport, label, screenshotDir) {
  const { targetId } = await cdp.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });

  await cdp.send("Page.enable", {}, sessionId);
  await cdp.send("Runtime.enable", {}, sessionId);
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: viewport.width,
    height: viewport.height,
    deviceScaleFactor: 1,
    mobile: viewport.width < 600
  }, sessionId);
  await cdp.send("Page.navigate", { url }, sessionId);
  await waitForRuntime(cdp, sessionId, "document.readyState === 'complete'");
  await waitForRuntime(cdp, sessionId, "document.querySelector('[aria-label=\"Monitors\"]')");

  const proof = await evaluate(cdp, sessionId, async function exerciseHiddenMonitorTray() {
    const pause = () => new Promise((resolvePause) => setTimeout(resolvePause, 50));
    const monitorSection = document.querySelector('[aria-label="Monitors"]');

    if (!monitorSection) {
      throw new Error("monitor section missing");
    }

    const visibleButtons = [...monitorSection.querySelectorAll(".monitor-toggle")];
    if (visibleButtons.length < 2) {
      throw new Error(`expected at least two visible monitor buttons, found ${visibleButtons.length}`);
    }

    for (const button of visibleButtons.slice(0, 2)) {
      button.click();
      await pause();
    }

    const tray = monitorSection.querySelector(".hidden-monitor-tray");
    const trayText = tray?.textContent ?? "";
    const showAllButton = [...monitorSection.querySelectorAll("button")]
      .find((button) => /all monitors/i.test(button.textContent ?? "") && /show all/i.test(button.textContent ?? ""));

    if (!tray || !/2 hidden monitors/.test(trayText) || !showAllButton) {
      throw new Error(`hidden monitor tray did not expose Show all: ${trayText}`);
    }

    showAllButton.click();
    await pause();

    const visibleAfter = monitorSection.querySelectorAll(".monitor-toggle").length;
    const hiddenTrayCount = monitorSection.querySelectorAll(".hidden-monitor-tray").length;
    const horizontalOverflow = document.documentElement.scrollWidth > document.documentElement.clientWidth;

    return { trayText, visibleAfter, hiddenTrayCount, horizontalOverflow };
  });

  if (proof.hiddenTrayCount !== 0) {
    throw new Error(`${label}: hidden monitor tray remained after Show all`);
  }
  if (proof.visibleAfter < 2) {
    throw new Error(`${label}: monitors were not restored after Show all`);
  }
  if (proof.horizontalOverflow) {
    throw new Error(`${label}: horizontal overflow detected`);
  }

  const screenshot = await cdp.send("Page.captureScreenshot", { format: "png", fromSurface: true }, sessionId);
  const screenshotPath = join(screenshotDir, `desktop-preview-${label}.png`);
  writeFileSync(screenshotPath, Buffer.from(screenshot.data, "base64"));
  await cdp.send("Target.closeTarget", { targetId });

  return { label, viewport, screenshotPath, ...proof };
}

async function evaluate(cdp, sessionId, fn) {
  const expression = `(${fn.toString()})()`;
  const result = await cdp.send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true
  }, sessionId);

  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description ?? "browser evaluation failed");
  }

  return result.result.value;
}

async function waitForRuntime(cdp, sessionId, expression) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < 10000) {
    const result = await cdp.send("Runtime.evaluate", { expression, returnByValue: true }, sessionId);
    if (result.result.value) {
      return;
    }
    await delay(100);
  }

  throw new Error(`Timed out waiting for browser condition: ${expression}`);
}

class CdpClient {
  static connect(url) {
    return new Promise((resolveClient, reject) => {
      const socket = new WebSocket(url);
      const client = new CdpClient(socket);
      socket.addEventListener("open", () => resolveClient(client), { once: true });
      socket.addEventListener("error", (event) => reject(event.error ?? new Error("CDP socket error")), { once: true });
    });
  }

  constructor(socket) {
    this.nextId = 1;
    this.pending = new Map();
    this.socket = socket;
    socket.addEventListener("message", (event) => this.receive(event.data));
  }

  send(method, params = {}, sessionId = undefined) {
    const id = this.nextId++;
    const message = { id, method, params };
    if (sessionId) {
      message.sessionId = sessionId;
    }

    return new Promise((resolveSend, reject) => {
      this.pending.set(id, { resolve: resolveSend, reject });
      this.socket.send(JSON.stringify(message));
    });
  }

  receive(data) {
    const message = JSON.parse(data);
    const pending = this.pending.get(message.id);
    if (!pending) {
      return;
    }

    this.pending.delete(message.id);
    if (message.error) {
      pending.reject(new Error(message.error.message));
    } else {
      pending.resolve(message.result ?? {});
    }
  }

  close() {
    this.socket.close();
  }
}

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

function findChromium() {
  const result = spawnSync("sh", [
    "-lc",
    "command -v chromium || command -v chromium-browser || command -v google-chrome || command -v brave || true"
  ], { encoding: "utf8" });
  return result.stdout.trim() || undefined;
}

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, { stdio: "inherit" });
  if (result.status !== 0) {
    fail(`${command} ${commandArgs.join(" ")} failed`);
  }
}

function waitForHttp(url) {
  return waitUntil(async () => {
    try {
      const response = await fetch(url);
      return response.ok;
    } catch {
      return false;
    }
  }, `HTTP server ${url}`);
}

async function waitForCdp(port) {
  let version;
  await waitUntil(async () => {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/version`);
      version = await response.json();
      return Boolean(version.webSocketDebuggerUrl);
    } catch {
      return false;
    }
  }, "Chromium DevTools endpoint");
  return version.webSocketDebuggerUrl;
}

async function waitUntil(check, label) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < 10000) {
    if (await check()) {
      return;
    }
    await delay(100);
  }

  throw new Error(`Timed out waiting for ${label}`);
}

function delay(ms) {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, ms));
}

async function terminateChild(child) {
  if (child.exitCode !== null || child.killed) {
    return;
  }

  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolveExit) => child.once("exit", resolveExit)),
    delay(2000).then(() => {
      if (child.exitCode === null) {
        child.kill("SIGKILL");
      }
    })
  ]);
}

async function removeWithRetries(path) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      rmSync(path, { recursive: true, force: true });
      return;
    } catch (error) {
      if (attempt === 4) {
        throw error;
      }
      await delay(100);
    }
  }
}

function freePort() {
  return new Promise((resolvePort, reject) => {
    import("node:net").then(({ createServer }) => {
      const server = createServer();
      server.listen(0, "127.0.0.1", () => {
        const address = server.address();
        server.close(() => resolvePort(address.port));
      });
      server.on("error", reject);
    }, reject);
  });
}

function fail(message) {
  console.error(`verify-desktop-preview: ${message}`);
  process.exit(1);
}

await main();
