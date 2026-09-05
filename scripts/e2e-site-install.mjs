#!/usr/bin/env node
/** Built homepage interaction checks. Uses an existing Playwright installation, like e2e-desktop-ui.mjs. */
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { extname, resolve, sep } from "node:path";

const root = resolve("dist/site");
const guide = readFileSync("apps/docs/docs/guide/install.md", "utf8");
const platforms = ["automatic", "arch", "ubuntu", "debian", "fedora", "opensuse", "nix", "portable", "source"];
const automatic = "curl -fsSL https://loopwire.app/install.sh | bash";
const mime = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".svg": "image/svg+xml" };
let playwright;
for (const base of [import.meta.url, "file:///usr/lib/e2e-resolver.js"]) {
  try { playwright = createRequire(base)("playwright"); break; } catch { /* Try the existing system installation. */ }
}
assert.ok(playwright, "Install Playwright separately or set NODE_PATH; this test does not download dependencies.");
const server = createServer((request, response) => {
  try {
    const path = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
    const file = resolve(root, `.${path.endsWith("/") ? `${path}index.html` : path}`);
    if (!file.startsWith(`${root}${sep}`)) { response.writeHead(403).end(); return; }
    response.writeHead(200, { "content-type": mime[extname(file)] ?? "application/octet-stream" });
    response.end(readFileSync(file));
  } catch { response.writeHead(404).end(); }
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const url = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await playwright.chromium.launch({
    headless: true,
    ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
      ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } : {})
  });
  const context = await browser.newContext({ permissions: ["clipboard-read", "clipboard-write"], reducedMotion: "reduce" });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(url);
  assert.equal(await page.locator('[role="tab"]').count(), platforms.length);
  assert.equal(await page.locator('[role="tabpanel"]:visible code').textContent(), automatic);
  assert.doesNotMatch(await page.locator("body").innerText(), /Pre-release today|Bunny deploy|VM proof pass/);
  console.log("PASS: automatic default and obsolete notice removed");

  for (const platform of platforms) {
    await page.locator(`#install-tab-${platform}`).click();
    assert.equal(await page.locator('[role="tab"][aria-selected="true"]').count(), 1);
    assert.equal(await page.locator('[role="tabpanel"]:visible').getAttribute("id"), `install-panel-${platform}`);
    const command = await page.locator('[role="tabpanel"]:visible code').textContent();
    execFileSync("bash", ["-n"], { input: command });
    assert.ok(guide.includes(command), `${platform} instructions must match the install guide`);
    await page.locator("[data-copy-install]").click();
    await page.waitForFunction(() => document.querySelector("[data-copy-install]").textContent === "Copied");
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), command);
  }
  console.log("PASS: all nine panels, shell command syntax, guide parity and selected-command clipboard");

  await page.locator("#install-tab-source").focus();
  for (const [key, platform] of [["ArrowRight", "automatic"], ["ArrowLeft", "source"], ["Home", "automatic"], ["End", "source"]]) {
    await page.keyboard.press(key);
    assert.equal(await page.evaluate(() => document.activeElement.id), `install-tab-${platform}`);
    assert.equal(await page.locator('[role="tabpanel"]:visible').getAttribute("id"), `install-panel-${platform}`);
  }
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.id), "install-panel-source");
  await page.evaluate(() => { navigator.clipboard.writeText = async () => { throw new Error("Clipboard denied"); }; });
  await page.locator("[data-copy-install]").click();
  await page.waitForFunction(() => document.querySelector("#copy-status").textContent.includes("copy it manually"));
  assert.ok(await page.locator("#copy-status").isVisible());
  await page.locator("#install-tab-automatic").click();
  assert.equal(await page.locator("#copy-status").textContent(), "");
  console.log("PASS: keyboard navigation, focus order and visible clipboard failure/recovery");

  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    for (const platform of platforms) {
      await page.locator(`#install-tab-${platform}`).click();
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${platform} overflows at ${width}px`);
    }
  }
  assert.deepEqual(errors, []);
  console.log("PASS: all tabs at 320/390/768/1440px without page overflow or browser errors");

  const noJs = await browser.newContext({ javaScriptEnabled: false });
  const plain = await noJs.newPage();
  await plain.goto(url);
  assert.equal(await plain.locator('[role="tabpanel"]:visible code').textContent(), automatic);
  assert.equal(await plain.locator('[role="tablist"]').isVisible(), false);
  assert.equal(await plain.locator("[data-copy-install]").isVisible(), false);
  assert.ok(await plain.getByRole("link", { name: "all platform instructions" }).isVisible());
  console.log("PASS: no-JavaScript installer and platform-guide fallback");
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
