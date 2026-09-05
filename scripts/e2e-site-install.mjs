#!/usr/bin/env node
/** Built homepage interaction checks. Uses an existing Playwright installation, like e2e-desktop-ui.mjs. */
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { extname, resolve, sep } from "node:path";

const root = resolve("dist/site");
const guide = readFileSync("apps/docs/docs/guide/install.md", "utf8");
const platforms = ["automatic", "arch", "ubuntu", "debian", "fedora", "opensuse", "nix", "portable", "source"];
const automatic = "curl -fsSL https://loopwire.app/install.sh | bash";
const proofIndex = process.argv.indexOf("--screenshots");
const proofDir = proofIndex < 0 ? undefined : process.argv[proofIndex + 1];
assert.ok(proofIndex < 0 || proofDir, "--screenshots requires an output directory");
const mime = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png",
  ".svg": "image/svg+xml", ".woff2": "font/woff2" };
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
  assert.equal(await page.locator(".capability-row, .install-card, .shot").count(), 0);
  assert.equal(await page.getByRole("link", { name: "Loopwire home" }).count(), 1);
  assert.ok(await page.locator(".hero .product-preview img").isVisible());
  await page.evaluate(() => document.fonts.ready);
  assert.ok(await page.evaluate(() => [...document.fonts].some((font) => font.family === "Sora" && font.status === "loaded")));
  const framing = await page.locator(".hero, .install, .install-controls, .product-preview, button, .wordmark").evaluateAll(
    (elements) => elements.map((element) => {
      const style = getComputedStyle(element);
      return [style.borderRadius, style.boxShadow, style.textShadow, style.filter, style.borderTopWidth];
    })
  );
  for (const style of framing) assert.deepEqual(style, ["0px", "none", "none", "none", "0px"]);
  console.log("PASS: automatic default and obsolete notice removed");

  const paletteColors = new Set();
  for (const platform of platforms) {
    await page.locator(`#install-tab-${platform}`).click();
    assert.equal(await page.locator('[role="tab"][aria-selected="true"]').count(), 1);
    assert.equal(await page.locator('[role="tabpanel"]:visible').getAttribute("id"), `install-panel-${platform}`);
    paletteColors.add(await page.evaluate(() => getComputedStyle(document.documentElement).backgroundColor));
    const command = await page.locator('[role="tabpanel"]:visible code').textContent();
    execFileSync("bash", ["-n"], { input: command });
    assert.ok(guide.includes(command), `${platform} instructions must match the install guide`);
    await page.locator("[data-copy-install]").click();
    await page.waitForFunction(() => document.querySelector("[data-copy-install]").textContent === "Copied");
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), command);
  }
  assert.equal(paletteColors.size, platforms.length, "every tab selects a distinct background palette");
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

  const motionContext = await browser.newContext({
    permissions: ["clipboard-read", "clipboard-write"], reducedMotion: "no-preference", viewport: { width: 1440, height: 1000 }
  });
  const motion = await motionContext.newPage();
  await motion.addInitScript(() => {
    const clear = CanvasRenderingContext2D.prototype.clearRect;
    window.signalDraws = 0;
    CanvasRenderingContext2D.prototype.clearRect = function (...args) {
      window.signalDraws += 1;
      return clear.apply(this, args);
    };
  });
  motion.on("pageerror", (error) => errors.push(error.message));
  await motion.goto(url);
  await motion.locator('#signal-field[data-motion="interactive"]').waitFor();
  await motion.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
  const pixels = () => motion.locator("#signal-field").evaluate((canvas) => canvas.toDataURL());
  const changedPixels = (previous) => motion.waitForFunction(
    (before) => document.querySelector("#signal-field").toDataURL() !== before, previous, { timeout: 3500 }
  );
  let before = await pixels();
  const idleDraws = await motion.evaluate(() => window.signalDraws);
  await motion.waitForTimeout(180);
  assert.equal(await pixels(), before, "background does not run an idle drawing loop");
  assert.equal(await motion.evaluate(() => window.signalDraws), idleDraws, "idle canvas is not repeatedly redrawn");
  await motion.mouse.move(1100, 770);
  await changedPixels(before);
  await motion.waitForTimeout(800);
  before = await pixels();
  await motion.mouse.click(1200, 900);
  await changedPixels(before);
  await motion.waitForTimeout(1000);

  const startingColor = await motion.evaluate(() => getComputedStyle(document.documentElement).backgroundColor);
  await motion.locator("#install-tab-ubuntu").click();
  await motion.waitForFunction((start) => getComputedStyle(document.documentElement).backgroundColor !== start, startingColor);
  const intermediateColor = await motion.evaluate(() => getComputedStyle(document.documentElement).backgroundColor);
  await motion.waitForTimeout(750);
  const finalColor = await motion.evaluate(() => getComputedStyle(document.documentElement).backgroundColor);
  assert.notEqual(intermediateColor, startingColor, "GSAP begins the palette transition");
  assert.notEqual(intermediateColor, finalColor, "palette changes over time, not just in one CSS assignment");

  // Delay clipboard completion so its distinct success pulse is measured after the generic click has settled.
  await motion.evaluate(() => {
    navigator.clipboard.writeText = () => new Promise((resolve) => { window.finishCopy = resolve; });
  });
  await motion.locator("[data-copy-install]").click();
  await motion.waitForTimeout(1000);
  before = await pixels();
  await motion.evaluate(() => window.finishCopy());
  await motion.waitForFunction(() => document.querySelector("[data-copy-install]").textContent === "Copied");
  await changedPixels(before);
  await motion.waitForTimeout(1300);
  console.log("PASS: real canvas pointer/click/copy reactions, finite motion, and animated palette transitions");

  await motion.emulateMedia({ reducedMotion: "reduce" });
  await motion.locator('#signal-field[data-motion="reduced"]').waitFor();
  await motion.waitForTimeout(80);
  before = await pixels();
  await motion.mouse.move(600, 800);
  await motion.mouse.click(1200, 900);
  await motion.waitForTimeout(250);
  assert.equal(await pixels(), before, "reduced motion suppresses pointer/click animation");
  await motion.locator("[data-copy-install]").click();
  await motion.evaluate(() => window.finishCopy());
  await motion.waitForTimeout(120);
  assert.equal(await pixels(), before, "reduced motion suppresses successful-copy animation");
  await motion.locator("#install-tab-fedora").click();
  assert.notEqual(await motion.evaluate(() => getComputedStyle(document.documentElement).backgroundColor), finalColor);
  await motion.waitForTimeout(80);
  before = await pixels();
  await motion.waitForTimeout(200);
  assert.equal(await pixels(), before, "reduced-motion palette changes settle immediately");
  console.log("PASS: live reduced-motion preference suppresses animation while retaining palette/copy behavior");

  // Simulate the visibility boundary and count actual canvas draws, rather than trusting the debug attribute alone.
  await motion.emulateMedia({ reducedMotion: "no-preference" });
  await motion.mouse.move(900, 700);
  await motion.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, value: true });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  const hiddenDraws = await motion.evaluate(() => window.signalDraws);
  await motion.mouse.move(1100, 820);
  await motion.waitForTimeout(200);
  assert.equal(await motion.evaluate(() => window.signalDraws), hiddenDraws, "hidden document stops drawing");
  await motion.evaluate(() => {
    delete document.hidden;
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await motion.waitForTimeout(80);
  before = await pixels();
  await motion.mouse.move(850, 720);
  await changedPixels(before);
  console.log("PASS: visibility-boundary simulation stops drawing and restores interactions");

  const noCanvas = await browser.newPage();
  await noCanvas.addInitScript(() => { HTMLCanvasElement.prototype.getContext = () => null; });
  await noCanvas.goto(url);
  await noCanvas.locator("#install-tab-arch").click();
  assert.equal(await noCanvas.locator('[role="tabpanel"]:visible').getAttribute("id"), "install-panel-arch");
  assert.deepEqual(errors, []);
  console.log("PASS: unavailable canvas does not break platform selection");

  if (proofDir) {
    mkdirSync(proofDir, { recursive: true });
    const proof = await motionContext.newPage();
    await proof.goto(url);
    await proof.locator('#signal-field[data-motion="interactive"]').waitFor();
    await proof.evaluate(() => document.fonts.ready);
    await proof.screenshot({ path: resolve(proofDir, "desktop.png"), fullPage: true });
    await proof.locator("#install-tab-ubuntu").click();
    await proof.waitForTimeout(1000);
    await proof.screenshot({ path: resolve(proofDir, "ubuntu-palette.png"), fullPage: true });
    await proof.locator("#install-tab-automatic").click();
    await proof.waitForTimeout(1000);
    await proof.locator("[data-copy-install]").click();
    await proof.waitForFunction(() => document.querySelector("[data-copy-install]").textContent === "Copied");
    await proof.waitForTimeout(260);
    await proof.screenshot({ path: resolve(proofDir, "copy-response.png"), fullPage: true, animations: "allow" });
    const mobile = await motionContext.newPage();
    await mobile.setViewportSize({ width: 390, height: 844 });
    await mobile.goto(url);
    await mobile.locator('#signal-field[data-motion="interactive"]').waitFor();
    await mobile.evaluate(() => document.fonts.ready);
    await mobile.screenshot({ path: resolve(proofDir, "mobile.png"), fullPage: true });
    console.log(`Screenshot proofs written to ${proofDir}`);
  }
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
