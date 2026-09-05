#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { parseInstalledHashes, verifyInstalledStage, verifyLifecycle } from "./verify-apt-repository-vm-proof.mjs";

const directory = await mkdtemp(path.join(tmpdir(), "loopwire-apt-proof-test-"));
const baseline = "0.1.0-1ubuntu24.04";
const upgrade = "0.1.0+aptfixture1-1ubuntu24.04";
const baseUrl = "https://127.0.0.1:8443";
const expectedHashes = Object.fromEntries([
  "/usr/bin/loopwire", "/usr/bin/loopwire-dsp-provider", "/usr/bin/loopwire-jack-ports",
  "/usr/bin/loopwire-detect-audio", "/usr/lib/loopwire/loopwire-gui",
  "/usr/share/applications/loopwire.desktop", "/usr/share/icons/hicolor/scalable/apps/loopwire.svg",
].map((name) => [name, "a".repeat(64)]));
const transitions = [
  `install\t${baseline}\tinstalled`, `reinstall\t${baseline}\tinstalled`, `upgrade\t${upgrade}\tinstalled`,
  `rollback\t${baseline}\tinstalled`, `remove\t${baseline}\tabsent`,
].join("\n");
let passed = 0;
async function test(name, action) {
  await action();
  passed += 1;
  console.log(`PASS ${name}`);
}
async function stageFixture() {
  await mkdir(path.join(directory, "install"), { recursive: true });
  const files = {
    "package-metadata.tsv": `loopwire\t${baseline}\tamd64\tinstall ok installed\n`,
    "package-files.txt": `${Object.keys(expectedHashes).join("\n")}\n`,
    "installed-files.sha256": `${Object.entries(expectedHashes).map(([name, hash]) => `${hash}  ${name}`).join("\n")}\n`,
    "apt-policy.txt": `loopwire:\n Installed: ${baseline}\n Candidate: ${baseline}\n 500 ${baseUrl} ubuntu-24.04/main amd64 Packages\n`,
    "background-help.txt": "Usage: Loopwire background restore\n",
    "dsp-provider-help.txt": "Usage: Loopwire DSP provider\n",
    "jack-provider-help.txt": "Usage: Loopwire JACK provider\n",
    "detect-audio.json": "{\"backends\":[]}\n",
    "gui-ldd.txt": "libgtk-3.so => /lib/libgtk-3.so\nlibwebkit2gtk-4.1.so => /lib/libwebkit2gtk-4.1.so\n",
    "gui-launch-status.txt": "0\n", "gui-window-ids.txt": "1234\n", "gui-window-names.txt": "Loopwire\n",
    "gui-launch.log": "", "xvfb.log": "",
  };
  for (const [name, content] of Object.entries(files)) await writeFile(path.join(directory, "install", name), content);
}
async function verifyStage() {
  await verifyInstalledStage(directory, "install", baseline, baseUrl, expectedHashes);
}
async function change(name, transform) {
  const file = path.join(directory, "install", name);
  await writeFile(file, transform(await readFile(file, "utf8")));
}
try {
  await test("complete ordered lifecycle accepted", () => verifyLifecycle(transitions, baseline, upgrade));
  await test("missing reinstall rejected", () => assert.throws(() => verifyLifecycle(transitions.split("\n").filter((line) => !line.startsWith("reinstall")).join("\n"), baseline, upgrade), /lifecycle transitions/));
  await test("rollback remaining at new version rejected", () => assert.throws(() => verifyLifecycle(transitions.replace(`rollback\t${baseline}`, `rollback\t${upgrade}`), baseline, upgrade), /lifecycle transitions/));
  await test("fabricated summary pass is insufficient", () => assert.throws(() => verifyLifecycle("pass", baseline, upgrade), /lifecycle transitions/));
  await test("duplicate file hash rejected", () => assert.throws(() => parseInstalledHashes(`${"a".repeat(64)}  /usr/bin/loopwire\n${"b".repeat(64)}  /usr/bin/loopwire\n`), /duplicate/));
  await test("parent traversal hash rejected", () => assert.throws(() => parseInstalledHashes(`${"a".repeat(64)}  /usr/../etc/passwd\n`), /invalid/));
  await stageFixture();
  await test("complete stage fixture accepted", verifyStage);
  for (const [name, file, mutation, pattern] of [
    ["changed installed bytes rejected", "installed-files.sha256", (value) => value.replace("a".repeat(64), "b".repeat(64)), /signed package payload/],
    ["wrong installed version rejected", "package-metadata.tsv", (value) => value.replace(baseline, upgrade), /package metadata/],
    ["local file installation without origin rejected", "apt-policy.txt", (value) => value.replace(baseUrl, "file:\/tmp/local"), /repository origin/],
    ["unresolved GUI dependency rejected", "gui-ldd.txt", (value) => `${value}libmissing.so => not found\n`, /linkage/],
    ["unrelated X11 window rejected", "gui-window-names.txt", () => "xterm\n", /application window/],
    ["failed GUI process rejected", "gui-launch-status.txt", () => "124\n", /GUI launch/],
    ["GUI panic rejected", "gui-launch.log", () => "thread main panicked\n", /fatal GUI log/],
    ["empty provider output rejected", "dsp-provider-help.txt", () => "", /empty evidence/],
    ["missing installed helper rejected", "package-files.txt", (value) => value.replace("/usr/bin/loopwire-dsp-provider\n", ""), /missing/],
  ]) {
    await stageFixture();
    await change(file, mutation);
    await test(name, () => assert.rejects(verifyStage, pattern));
  }
  console.log(`APT VM proof verifier tests passed: ${passed}`);
} finally {
  await rm(directory, { recursive: true, force: true });
}
