#!/usr/bin/env node
/**
 * End-to-end UI harness (browser fallback path, SEED-001 / E2E-01, E2E-02).
 *
 * Builds the desktop frontend, serves `apps/desktop/dist` on a strict local port,
 * drives system Playwright Chromium (headless) through the core flows, and prints
 * a pass/fail table. Exits non-zero on any failure.
 *
 * This suite runs the frontend WITHOUT the Tauri bridge, so it asserts
 * preview-mode behavior only: DOM state, cables, selection, persistence via
 * localStorage. It makes NO claims about host (PipeWire) apply. The real-shell
 * WebDriver smoke lives in scripts/e2e-desktop-shell.mjs.
 *
 * Host requirements (documented manual validation, not part of `pnpm check`):
 *   - System-wide Playwright at /usr/lib/node_modules (see AGENTS.md) with
 *     browsers cached in ~/.cache/ms-playwright, or NODE_PATH resolving playwright.
 *   - Port 5199 free (this script never kills existing listeners; pass --port N).
 *
 * Usage: node scripts/e2e-desktop-ui.mjs [--port N] [--skip-build]
 */
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFileSync, existsSync, statSync } from "node:fs";
import { join, resolve, extname, normalize } from "node:path";

const args = process.argv.slice(2);
const port = Number(readOption("--port") ?? "5199");
const skipBuild = args.includes("--skip-build");
const distDir = resolve("apps/desktop/dist");

const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".json": "application/json",
  ".woff2": "font/woff2",
  ".ico": "image/x-icon"
};

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
  console.error(`e2e-desktop-ui: ${message}`);
  process.exit(1);
}

function loadPlaywright() {
  const bases = [import.meta.url, "file:///usr/lib/e2e-resolver.js"];
  for (const base of bases) {
    try {
      return createRequire(base)("playwright");
    } catch {
      // try next base
    }
  }
  fail(
    "playwright not found. Install it system-wide (see AGENTS.md Playwright notes) " +
      "or run with NODE_PATH=/usr/lib/node_modules."
  );
}

function buildFrontend() {
  const result = spawnSync("pnpm", ["--filter", "@loopwire/desktop", "build"], { stdio: "inherit" });
  if (result.status !== 0) {
    fail("frontend build failed");
  }
}

/** Tiny static file server with SPA fallback; strict port, never evicts listeners. */
function serveDist() {
  return new Promise((resolveServer, reject) => {
    const server = createServer((request, response) => {
      const requestPath = normalize(decodeURIComponent(new URL(request.url, "http://localhost").pathname));
      let filePath = join(distDir, requestPath);
      if (!filePath.startsWith(distDir) || !existsSync(filePath) || statSync(filePath).isDirectory()) {
        filePath = join(distDir, "index.html");
      }
      try {
        const body = readFileSync(filePath);
        response.writeHead(200, { "content-type": mime[extname(filePath)] ?? "application/octet-stream" });
        response.end(body);
      } catch {
        response.writeHead(404);
        response.end("not found");
      }
    });
    server.on("error", (error) => {
      if (error.code === "EADDRINUSE") {
        reject(new Error(`port ${port} is already in use; pass --port N (this harness never kills listeners)`));
      } else {
        reject(error);
      }
    });
    server.listen(port, "127.0.0.1", () => resolveServer(server));
  });
}

const cableSelector = "svg.cable-layer path.cable";
const sourceCardSelector = 'article[aria-label^="Source "]';

async function cableCount(page) {
  return page.locator(cableSelector).count();
}

async function expectEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function steps(page) {
  return [
    {
      name: "preview mode is honest (no Tauri bridge, no host-apply claims)",
      async run() {
        const bridge = await page.evaluate(() => typeof window.__TAURI_INTERNALS__);
        await expectEqual(bridge, "undefined", "Tauri bridge presence");
      }
    },
    {
      name: "empty state renders with no devices",
      async run() {
        await page.waitForSelector('button:has-text("New Virtual Device")');
        await expectEqual(await page.locator("[data-device-row]").count(), 0, "sidebar rows");
        await page.waitForSelector('text=Create your first virtual audio device');
      }
    },
    {
      name: "create device: auto-rename, default Pass-Thru graph, 2 cables",
      async run() {
        await page.click('button:has-text("New Virtual Device")');
        const rename = page.locator("input.rename");
        await rename.waitFor();
        await expectEqual(await rename.inputValue(), "Loopwire Device 1", "auto-name");
        await rename.fill("Test Rig");
        await rename.press("Enter");
        await page.waitForSelector('h1:has-text("Test Rig")');
        await expectEqual(await page.locator("[data-device-row]").count(), 1, "sidebar rows");
        await expectEqual(await page.locator(sourceCardSelector).count(), 1, "source cards");
        await page.waitForSelector('article[aria-label="Source Pass-Thru"]');
        await expectEqual(await cableCount(page), 2, "cables");
        // Nothing is selected right after device creation, so Delete is inert.
        await expectEqual(await page.locator('button:has-text("Delete")').isDisabled(), true, "Delete disabled with no selection");
      }
    },
    {
      name: "add source from menu grows the cable count",
      async run() {
        await page.click('button[aria-label="Add source"]');
        await page.click('button.item[data-item-id="browser"]');
        await expectEqual(await page.locator(sourceCardSelector).count(), 2, "source cards");
        await expectEqual(await cableCount(page), 4, "cables");
      }
    },
    {
      name: "toggle source Off dims its cables",
      async run() {
        const card = page.locator('article[aria-label="Source Browser"]');
        await card.locator('button[role="switch"]').click();
        await expectEqual(await card.locator('button[role="switch"]').getAttribute("aria-checked"), "false", "pill state");
        await expectEqual(await page.locator("article.card.off").count(), 1, "off cards");
        await expectEqual(await page.locator(`${cableSelector}.dimmed`).count(), 2, "dimmed cables");
      }
    },
    {
      name: "select card enables footer Delete; Delete removes it",
      async run() {
        const deleteButton = page.locator('button:has-text("Delete")');
        await page.click('article[aria-label="Source Browser"]');
        await expectEqual(await page.locator("article.card.selected").count(), 1, "selected cards");
        await expectEqual(await deleteButton.isDisabled(), false, "Delete enabled after selection");
        await deleteButton.click();
        await expectEqual(await page.locator(sourceCardSelector).count(), 1, "source cards after delete");
        await expectEqual(await cableCount(page), 2, "cables after delete");
        await expectEqual(await page.locator(`${cableSelector}.dimmed`).count(), 0, "dimmed cables after delete");
      }
    },
    {
      name: "Hide Monitors collapses the monitors column (and restores)",
      async run() {
        await page.click('button:has-text("Hide Monitors")');
        await page.waitForSelector(".headers.monitors-hidden");
        await expectEqual(await page.locator('button[aria-label="Add monitor"]').count(), 0, "monitor column header");
        await page.click('button:has-text("Show Monitors")');
        await page.waitForSelector('button[aria-label="Add monitor"]');
      }
    },
    {
      name: "reload restores state from localStorage (loopwire.state.v1)",
      async run() {
        const raw = await page.evaluate(() => localStorage.getItem("loopwire.state.v1"));
        if (!raw) {
          throw new Error("localStorage key loopwire.state.v1 missing before reload");
        }
        await page.reload();
        await page.waitForSelector('h1:has-text("Test Rig")');
        await expectEqual(await page.locator("[data-device-row]").count(), 1, "sidebar rows after reload");
        await expectEqual(await page.locator(sourceCardSelector).count(), 1, "source cards after reload");
        await expectEqual(await cableCount(page), 2, "cables after reload");
      }
    },
    {
      name: "drag-reorder moves a sidebar row",
      async run() {
        await page.click('button:has-text("New Virtual Device")');
        const rename = page.locator("input.rename");
        await rename.waitFor();
        await rename.press("Enter");
        await expectEqual(await page.locator("[data-device-row]").count(), 2, "sidebar rows");

        const rows = page.locator("[data-device-row]");
        const orderBefore = await rows.evaluateAll((nodes) => nodes.map((node) => node.dataset.deviceRow));
        const firstBox = await rows.nth(0).boundingBox();
        const secondBox = await rows.nth(1).boundingBox();
        await page.mouse.move(secondBox.x + secondBox.width / 2, secondBox.y + secondBox.height / 2);
        await page.mouse.down();
        await page.mouse.move(firstBox.x + firstBox.width / 2, firstBox.y + 2, { steps: 12 });
        await page.mouse.up();

        const orderAfter = await rows.evaluateAll((nodes) => nodes.map((node) => node.dataset.deviceRow));
        await expectEqual(orderAfter.join(","), [orderBefore[1], orderBefore[0]].join(","), "row order after drag");
      }
    }
  ];
}

async function main() {
  const playwright = loadPlaywright();

  if (!skipBuild) {
    buildFrontend();
  }
  if (!existsSync(join(distDir, "index.html"))) {
    fail(`missing ${join(distDir, "index.html")} — run pnpm --filter @loopwire/desktop build`);
  }

  const server = await serveDist();
  let browser;
  const results = [];
  let failed = false;

  try {
    try {
      browser = await playwright.chromium.launch({ headless: true });
    } catch {
      browser = await playwright.chromium.launch({ headless: true, executablePath: "/usr/bin/chromium" });
    }
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    await page.goto(`http://127.0.0.1:${port}/`);

    for (const step of steps(page)) {
      if (failed) {
        results.push({ name: step.name, status: "skipped", detail: "previous step failed" });
        continue;
      }
      try {
        await step.run();
        results.push({ name: step.name, status: "pass", detail: "" });
      } catch (error) {
        failed = true;
        results.push({ name: step.name, status: "FAIL", detail: error.message });
      }
    }
  } finally {
    await browser?.close();
    server.close();
  }

  const width = Math.max(...results.map((result) => result.name.length));
  console.log(`\n${"flow".padEnd(width)}  result`);
  console.log(`${"-".repeat(width)}  ------`);
  for (const result of results) {
    console.log(`${result.name.padEnd(width)}  ${result.status}${result.detail ? `  (${result.detail})` : ""}`);
  }
  console.log("");

  if (failed) {
    fail("one or more flows failed");
  }
  console.log(`e2e-desktop-ui: ${results.length} flows passed (preview mode, no host-apply claims)`);
}

await main();
