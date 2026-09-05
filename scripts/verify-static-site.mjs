#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { lstatSync, readFileSync, readdirSync, statSync } from "node:fs";
import { extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const distDir = resolve(repoRoot, "dist/site");
const installerSource = resolve(repoRoot, "scripts/install.sh");

const homepage = readRequired("index.html");
const docsIndex = readRequired("docs/index.html");
const basicUsage = readRequired("docs/guide/basic-usage.html");
const robots = readRequired("robots.txt");
const sitemap = readRequired("sitemap.xml");
const installer = readRequired("install.sh");

assertContains(homepage, ">Loopwire</h1>", "homepage h1");
assertContains(homepage, "<link rel=\"canonical\" href=\"https://loopwire.app/\">", "homepage canonical");
assertContains(homepage, "\"@type\":\"SoftwareApplication\"", "JSON-LD software type");
assertContains(homepage, "PipeWire-first virtual audio routing", "homepage description");
assertContains(homepage, "curl -fsSL https://loopwire.app/install.sh | bash", "default installer command");
assertContains(homepage, 'role="tablist"', "platform install tabs");
for (const platform of ["automatic", "arch", "ubuntu", "debian", "fedora", "opensuse", "nix", "portable", "source"]) {
  assertContains(homepage, `id="install-tab-${platform}"`, `${platform} install tab`);
  assertContains(homepage, `id="install-panel-${platform}"`, `${platform} install panel`);
}
if (homepage.includes("Signed public artifacts and the curl installer stay gated")) {
  fail("homepage still describes published releases as gated");
}
assertContains(homepage, "href=\"/docs/\"", "docs primary link");
assertContains(homepage, "https://github.com/sandwichfarm/loopwire", "GitHub link");
assertContains(homepage, "https://github.com/sandwichfarm/loopwire/releases", "releases link");
assertContains(homepage, "Loopwire desktop shell showing one saved device", "homepage screenshot alt");
assertContains(homepage, "Diagnostics and hardware discovery", "ALSA capability label");

assertContains(docsIndex, "Loopwire Docs", "docs title");
assertContains(docsIndex, "/docs/guide/install.html", "docs install link");
assertContains(docsIndex, "/docs/guide/basic-usage.html", "docs basic usage link");
assertContains(basicUsage, "A practical first route", "basic usage walkthrough");

assertContains(robots, "Sitemap: https://loopwire.app/sitemap.xml", "robots sitemap pointer");
assertContains(sitemap, "<loc>https://loopwire.app/</loc>", "homepage sitemap entry");
assertContains(sitemap, "<loc>https://loopwire.app/docs/</loc>", "docs sitemap entry");
assertContains(sitemap, "<loc>https://loopwire.app/docs/guide/basic-usage.html</loc>", "basic usage sitemap entry");
assertSitemapCoversHtml(sitemap);

if (installer !== readFileSync(installerSource, "utf8")) {
  fail("dist/site/install.sh does not match scripts/install.sh");
}
execFileSync("bash", ["-n", resolve(distDir, "install.sh")], { stdio: "pipe" });

assertNoSymlinks(distDir);
for (const htmlPath of listFiles(distDir).filter((path) => path.endsWith(".html"))) {
  verifyInternalReferences(htmlPath);
}

console.log("Static site verification passed for dist/site.");

function readRequired(relativePath) {
  const filePath = resolve(distDir, relativePath);
  const stats = statSync(filePath, { throwIfNoEntry: false });
  if (!stats?.isFile() || stats.size === 0) fail(`missing required built file: ${relativePath}`);
  return readFileSync(filePath, "utf8");
}

function assertContains(content, needle, label) {
  if (!content.includes(needle)) fail(`missing ${label}: ${needle}`);
}

function assertNoSymlinks(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    const stats = lstatSync(path);
    if (stats.isSymbolicLink()) fail(`built artifact contains symbolic link: ${relative(distDir, path)}`);
    if (stats.isDirectory()) assertNoSymlinks(path);
  }
}

function listFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? listFiles(path) : [path];
  });
}

function verifyInternalReferences(htmlPath) {
  const html = readFileSync(htmlPath, "utf8");
  for (const match of html.matchAll(/(?:href|src)="(\/[^"#?]+)(?:[?#][^"]*)?"/g)) {
    const pathname = decodeURIComponent(match[1]);
    if (!routeExists(pathname)) {
      fail(`broken internal reference in ${relative(distDir, htmlPath)}: ${pathname}`);
    }
  }
}

function assertSitemapCoversHtml(content) {
  for (const htmlPath of listFiles(distDir).filter(
    (path) => path.endsWith(".html") && !path.endsWith("404.html")
  )) {
    const route = publicRouteForHtml(relative(distDir, htmlPath).split(sep).join("/"));
    const url = new URL(route, "https://loopwire.app").toString();
    assertContains(content, `<loc>${url}</loc>`, `sitemap entry for ${route}`);
  }
}

function publicRouteForHtml(path) {
  if (path === "index.html") return "/";
  if (path.endsWith("/index.html")) return `/${path.slice(0, -"index.html".length)}`;
  return `/${path}`;
}

function routeExists(pathname) {
  const relativePath = pathname.replace(/^\/+/, "");
  const candidates = [];
  if (!relativePath || pathname.endsWith("/")) {
    candidates.push(join(distDir, relativePath, "index.html"));
  } else {
    candidates.push(join(distDir, relativePath));
    if (!extname(relativePath)) {
      candidates.push(join(distDir, `${relativePath}.html`));
      candidates.push(join(distDir, relativePath, "index.html"));
    }
  }
  return candidates.some((path) => statSync(path, { throwIfNoEntry: false })?.isFile());
}

function fail(message) {
  console.error(`verify-static-site: ${message}`);
  process.exit(1);
}
