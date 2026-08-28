#!/usr/bin/env node
import { copyFile, lstat, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const siteSource = resolve(repoRoot, "apps/site/dist");
const docsSource = resolve(repoRoot, "apps/docs/docs/.vitepress/dist");
const installerSource = resolve(repoRoot, "scripts/install.sh");
const output = resolve(repoRoot, "dist/site");

await assertDirectory(siteSource, "Astro output");
await assertDirectory(docsSource, "VitePress output");
await assertRegularFile(installerSource, "installer source");
await assertSafeTree(siteSource);
await assertSafeTree(docsSource);

if (await exists(join(siteSource, "docs"))) {
  fail("Astro output must not contain the reserved docs path");
}

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await copyTree(siteSource, output);
await copyTree(docsSource, join(output, "docs"));
await copyFile(installerSource, join(output, "install.sh"));
await writeSitemap(output);

await assertRegularFile(join(output, "index.html"), "combined homepage");
await assertRegularFile(join(output, "docs/index.html"), "combined docs homepage");
await assertRegularFile(join(output, "docs/guide/basic-usage.html"), "combined basic usage guide");

const [sourceInstaller, builtInstaller] = await Promise.all([
  readFile(installerSource),
  readFile(join(output, "install.sh"))
]);
if (!sourceInstaller.equals(builtInstaller)) {
  fail("combined installer differs from scripts/install.sh");
}

console.log(`Combined Astro and VitePress output at ${output}`);

async function writeSitemap(root) {
  const routes = (await listFiles(root))
    .filter((path) => path.endsWith(".html") && !path.endsWith("404.html"))
    .map((path) => publicRouteForHtml(relative(root, path).split(sep).join("/")))
    .sort();
  const locations = routes.map((route) => `  <url><loc>${new URL(route, "https://loopwire.app").toString()}</loc></url>`);
  const sitemap = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...locations,
    "</urlset>",
    ""
  ].join("\n");
  await writeFile(join(root, "sitemap.xml"), sitemap);
}

function publicRouteForHtml(path) {
  if (path === "index.html") return "/";
  if (path.endsWith("/index.html")) return `/${path.slice(0, -"index.html".length)}`;
  return `/${path}`;
}

async function listFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  entries.sort((left, right) => left.name.localeCompare(right.name));
  const files = [];
  for (const entry of entries) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) files.push(...(await listFiles(path)));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

async function copyTree(source, destination) {
  await mkdir(destination, { recursive: true });
  const entries = await readdir(source, { withFileTypes: true });
  entries.sort((left, right) => left.name.localeCompare(right.name));

  for (const entry of entries) {
    const sourcePath = join(source, entry.name);
    const destinationPath = join(destination, entry.name);
    const stats = await lstat(sourcePath);

    if (stats.isSymbolicLink()) fail(`refusing to copy symbolic link: ${sourcePath}`);
    if (stats.isDirectory()) {
      await copyTree(sourcePath, destinationPath);
      continue;
    }
    if (!stats.isFile()) fail(`refusing to copy unsupported filesystem entry: ${sourcePath}`);

    await mkdir(dirname(destinationPath), { recursive: true });
    await copyFile(sourcePath, destinationPath);
  }
}

async function assertSafeTree(root) {
  const entries = await readdir(root, { withFileTypes: true });
  for (const entry of entries) {
    const entryPath = join(root, entry.name);
    const stats = await lstat(entryPath);
    if (stats.isSymbolicLink()) fail(`build input contains symbolic link: ${entryPath}`);
    if (stats.isDirectory()) await assertSafeTree(entryPath);
    else if (!stats.isFile()) fail(`build input contains unsupported filesystem entry: ${entryPath}`);
  }
}

async function assertDirectory(path, label) {
  const stats = await lstat(path).catch(() => null);
  if (!stats?.isDirectory()) fail(`${label} directory does not exist: ${path}`);
}

async function assertRegularFile(path, label) {
  const stats = await lstat(path).catch(() => null);
  if (!stats?.isFile() || stats.size === 0) fail(`${label} is missing or empty: ${path}`);
}

async function exists(path) {
  return Boolean(await lstat(path).catch(() => null));
}

function fail(message) {
  throw new Error(`build-static-site: ${message}`);
}
