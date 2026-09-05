#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  parseInstalledHashes,
  parsePayloadRelease,
  parseReleaseChecksums,
  verifyReleaseAssetManifest,
  verifyReleaseSignature,
  verifyInstalledStage,
  verifyLifecycle,
  verifyPackageEntry,
  verifyRpmSignature,
} from "./verify-fedora-repository-vm-proof.mjs";

const directory = await mkdtemp(path.join(tmpdir(), "loopwire-fedora-proof-test-"));
const baseline = "0.1.0-1.fc44";
const upgrade = "0.1.0+dnffixture1-1.fc44";
const packageName = `loopwire-${baseline}.x86_64.rpm`;
const packageSha256 = "b".repeat(64);
const sourceSha256 = "c".repeat(64);
const fingerprint = "1234567890ABCDEF1234567890ABCDEF12345678";
const expectedHashes = Object.fromEntries([
  "/usr/bin/loopwire", "/usr/bin/loopwire-dsp-provider", "/usr/bin/loopwire-jack-ports",
  "/usr/bin/loopwire-detect-audio", "/usr/lib/loopwire/loopwire-gui",
  "/usr/share/applications/loopwire.desktop", "/usr/share/icons/hicolor/scalable/apps/loopwire.svg",
].map((name) => [name, "a".repeat(64)]));
const signature = `${packageName}:\n    Header OpenPGP V4 RSA/SHA512 signature, key fingerprint: ${fingerprint.toLowerCase()}: OK\n    Header SHA256 digest: OK\n    Payload SHA256 digest: OK\n`;
const transitions = [
  `install\t${baseline}\tinstalled`, `reinstall\t${baseline}\tinstalled`, `upgrade\t${upgrade}\tinstalled`,
  `rollback\t${baseline}\tinstalled`, `remove\t${baseline}\tabsent`,
].join("\n");
const releaseManifest = {
  schema: "loopwire.release-assets.v1",
  release: { tag: "v0.1.0", version: "0.1.0", gitHead: "e".repeat(40) },
  artifacts: [
    { name: packageName, kind: "native-rpm", target: "fedora-44", architecture: "x86_64", bytes: 123, sha256: sourceSha256 },
    { name: "loopwire-linux-x86_64.tar.gz", kind: "portable-archive", target: "linux-generic", architecture: "x86_64",
      bytes: 456, sha256: "d".repeat(64) },
  ],
};
const releaseExpected = { version: "0.1.0", rpmName: packageName, rpmBytes: 123, rpmSha256: sourceSha256,
  tarBytes: 456, tarSha256: "d".repeat(64) };
let passed = 0;

async function test(name, action) {
  await action();
  passed += 1;
  console.log(`PASS ${name}`);
}
async function stageFixture() {
  await rm(path.join(directory, "install"), { recursive: true, force: true });
  await mkdir(path.join(directory, "install"), { recursive: true });
  const files = {
    "package-metadata.tsv": `loopwire\t${baseline}\tx86_64\n`,
    "dnf-origin.txt": `loopwire|${baseline}|x86_64|loopwire\n`,
    "dnf-info.txt": `Installed packages\nName            : loopwire\nVersion         : 0.1.0\nRelease         : 1.fc44\nArchitecture    : x86_64\nFrom repository : loopwire\n`,
    "package-files.txt": `${Object.keys(expectedHashes).join("\n")}\n`,
    "installed-files.sha256": `${Object.entries(expectedHashes).map(([name, hash]) => `${hash}  ${name}`).join("\n")}\n`,
    "signed-package.sha256": `${packageSha256}  ${packageName}\n`,
    "rpm-signature.txt": signature,
    "background-help.txt": "Usage: Loopwire background restore\n",
    "dsp-provider-help.txt": "Usage: Loopwire DSP provider\n",
    "jack-provider-help.txt": "Usage: Loopwire JACK provider\n",
    "detect-audio.json": "{\"backends\":[]}\n",
    "gui-ldd.txt": "libgtk-3.so.0 => /lib64/libgtk-3.so.0\nlibwebkit2gtk-4.1.so.0 => /lib64/libwebkit2gtk-4.1.so.0\n",
    "gui-launch-status.txt": "0\n", "gui-window-ids.txt": "1234\n", "gui-window-names.txt": "Loopwire\n",
    "gui-launch.log": "", "xvfb.log": "",
  };
  for (const [name, content] of Object.entries(files)) await writeFile(path.join(directory, "install", name), content);
}
async function verifyStage() {
  await verifyInstalledStage(directory, "install", baseline, fingerprint, packageName, packageSha256, expectedHashes);
}
async function change(name, transform) {
  const file = path.join(directory, "install", name);
  await writeFile(file, transform(await readFile(file, "utf8")));
}

try {
  await test("complete ordered lifecycle accepted", () => verifyLifecycle(transitions, baseline, upgrade));
  await test("missing reinstall rejected", () => assert.throws(() => verifyLifecycle(
    transitions.split("\n").filter((line) => !line.startsWith("reinstall")).join("\n"), baseline, upgrade), /lifecycle transitions/));
  await test("rollback remaining at new version rejected", () => assert.throws(() => verifyLifecycle(
    transitions.replace(`rollback\t${baseline}`, `rollback\t${upgrade}`), baseline, upgrade), /lifecycle transitions/));
  await test("fabricated summary pass is insufficient", () => assert.throws(() => verifyLifecycle("pass", baseline, upgrade), /lifecycle transitions/));
  await test("duplicate file hash rejected", () => assert.throws(() => parseInstalledHashes(
    `${"a".repeat(64)}  /usr/bin/loopwire\n${"b".repeat(64)}  /usr/bin/loopwire\n`), /duplicate/));
  await test("parent traversal hash rejected", () => assert.throws(() => parseInstalledHashes(
    `${"a".repeat(64)}  /usr/../etc/passwd\n`), /invalid/));
  await test("selective signed release checksums accepted", () => assert.deepEqual(parseReleaseChecksums(
    `${sourceSha256}  ${packageName}\n${"d".repeat(64)}  loopwire-linux-x86_64.tar.gz\n${"e".repeat(64)}  release-assets.json\n`),
    new Map([[packageName, sourceSha256], ["loopwire-linux-x86_64.tar.gz", "d".repeat(64)],
      ["release-assets.json", "e".repeat(64)]])));
  await test("duplicate signed release checksum rejected", () => assert.throws(() => parseReleaseChecksums(
    `${sourceSha256}  ${packageName}\n${sourceSha256}  ${packageName}\n`), /duplicate/));
  await test("valid public release signature accepted and tamper rejected", async () => {
    const signing = path.join(directory, "release-signing");
    await mkdir(signing);
    const privateKey = path.join(signing, "private.pem");
    const publicKey = path.join(signing, "public.pem");
    const checksums = path.join(signing, "SHA256SUMS");
    const signatureFile = path.join(signing, "SHA256SUMS.sig");
    await writeFile(checksums, `${sourceSha256}  ${packageName}\n`);
    for (const args of [["genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", privateKey],
      ["pkey", "-in", privateKey, "-pubout", "-out", publicKey],
      ["dgst", "-sha256", "-sign", privateKey, "-out", signatureFile, checksums]]) {
      const result = spawnSync("openssl", args, { encoding: "utf8" });
      assert.equal(result.status, 0, result.stderr);
    }
    verifyReleaseSignature(checksums, signatureFile, publicKey);
    await writeFile(checksums, `${"0".repeat(64)}  ${packageName}\n`);
    assert.throws(() => verifyReleaseSignature(checksums, signatureFile, publicKey), /openssl verification failed/);
  });
  await test("exact public release manifest accepted", () => verifyReleaseAssetManifest(
    JSON.stringify(releaseManifest), releaseExpected));
  await test("wrong Fedora manifest target rejected", () => assert.throws(() => verifyReleaseAssetManifest(
    JSON.stringify({ ...releaseManifest, artifacts: releaseManifest.artifacts.map((entry, index) => index ? entry : { ...entry, target: "opensuse-tumbleweed" }) }),
    releaseExpected), /artifact count/));
  await test("wrong Fedora manifest hash rejected", () => assert.throws(() => verifyReleaseAssetManifest(
    JSON.stringify({ ...releaseManifest, artifacts: releaseManifest.artifacts.map((entry, index) => index ? entry : { ...entry, sha256: "0".repeat(64) }) }),
    releaseExpected), /Fedora release artifact/));
  await test("wrong public release version rejected", () => assert.throws(() => verifyReleaseAssetManifest(
    JSON.stringify({ ...releaseManifest, release: { ...releaseManifest.release, version: "0.2.0" } }), releaseExpected), /public release version/));
  const releaseText = "name=loopwire\nversion=0.1.0\narch=x86_64\nsource_date_epoch=1788115521\n";
  await test("exact portable RELEASE accepted", () => parsePayloadRelease(releaseText, "0.1.0"));
  await test("wrong portable RELEASE version rejected", () => assert.throws(() => parsePayloadRelease(
    releaseText.replace("version=0.1.0", "version=0.2.0"), "0.1.0"), /RELEASE version/));
  await test("valid RPM signature accepted", () => verifyRpmSignature(signature, fingerprint, packageName));
  await test("RPM NOKEY status rejected", () => assert.throws(() => verifyRpmSignature(
    signature.replace(": OK", ": NOKEY"), fingerprint, packageName), /failed/));
  await test("RPM signed by wrong key rejected", () => assert.throws(() => verifyRpmSignature(
    signature.replace(fingerprint.toLowerCase(), "0".repeat(40)), fingerprint, packageName), /wrong key/));
  await test("unsigned RPM output rejected", () => assert.throws(() => verifyRpmSignature(
    `${packageName}: digests OK\n`, fingerprint, packageName), /lacks/));
  const packageEntry = {
    name: "loopwire", version: "0.1.0", release: "1.fc44", architecture: "x86_64",
    path: `packages/${packageName}`, sourceReleaseSha256: sourceSha256,
    distributedSha256: packageSha256, size: 123,
  };
  await test("exact signed package manifest entry accepted", () => verifyPackageEntry(
    packageEntry, { version: "0.1.0", name: packageName }, packageSha256, sourceSha256, "fixture"));
  await test("public baseline source hash substitution rejected", () => assert.throws(() => verifyPackageEntry(
    { ...packageEntry, sourceReleaseSha256: "d".repeat(64) }, { version: "0.1.0", name: packageName },
    packageSha256, sourceSha256, "fixture"), /source release hash/));
  await test("distributed RPM substitution rejected", () => assert.throws(() => verifyPackageEntry(
    { ...packageEntry, distributedSha256: "d".repeat(64) }, { version: "0.1.0", name: packageName },
    packageSha256, sourceSha256, "fixture"), /distributed RPM hash/));

  await stageFixture();
  await test("complete Fedora installed stage accepted", verifyStage);
  for (const [name, file, mutation, pattern] of [
    ["changed installed bytes rejected", "installed-files.sha256", (value) => value.replace("a".repeat(64), "d".repeat(64)), /signed repository RPM payload/],
    ["wrong installed version rejected", "package-metadata.tsv", (value) => value.replace(baseline, upgrade), /package metadata/],
    ["local RPM installation without repository origin rejected", "dnf-origin.txt", (value) => value.replace("|loopwire\n", "|@commandline\n"), /repository origin/],
    ["wrong signed RPM digest rejected", "signed-package.sha256", (value) => value.replace(packageSha256, "d".repeat(64)), /signed RPM digest/],
    ["failed RPM signature rejected", "rpm-signature.txt", (value) => value.replace(": OK", ": NOT OK"), /signature verification failed/],
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
  console.log(`Fedora VM proof verifier tests passed: ${passed}`);
} finally {
  await rm(directory, { recursive: true, force: true });
}
