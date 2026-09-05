#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { parseInstalledHashes, parsePayloadRelease, parseReleaseChecksums, verifyReleaseSignature,
  verifyRpmSignature } from "./verify-fedora-repository-vm-proof.mjs";
import { verifyInstalledStage, verifyLifecycle, verifyPackageEntry, verifyReleaseAssetManifest,
  verifyZypperSearch, targetManifestRow } from "./verify-opensuse-repository-vm-proof.mjs";

const directory = await mkdtemp(path.join(tmpdir(), "loopwire-opensuse-proof-test-"));
const baseline = "0.1.0-1";
const upgrade = "0.1.0+zypperfixture1-1";
const packageName = `loopwire-${baseline}.x86_64.rpm`;
const packageSha256 = "b".repeat(64);
const sourceSha256 = "c".repeat(64);
const fingerprint = "1234567890ABCDEF1234567890ABCDEF12345678";
const expectedHashes = Object.fromEntries([
  "/usr/bin/loopwire", "/usr/bin/loopwire-dsp-provider", "/usr/bin/loopwire-jack-ports",
  "/usr/bin/loopwire-detect-audio", "/usr/lib/loopwire/loopwire-gui",
  "/usr/share/applications/loopwire.desktop", "/usr/share/icons/hicolor/scalable/apps/loopwire.svg",
].map((name) => [name, "a".repeat(64)]));
const signature = `${packageName}:\n    Header V4 RSA/SHA256 Signature, key ID ${fingerprint.slice(-16).toLowerCase()}: OK\n    Header SHA256 digest: OK\n    Payload SHA256 digest: OK\n`;
const transitions = [
  `install\t${baseline}\tinstalled`, `reinstall\t${baseline}\tinstalled`, `upgrade\t${upgrade}\tinstalled`,
  `rollback\t${baseline}\tinstalled`, `remove\t${baseline}\tabsent`,
].join("\n");
const releaseManifest = {
  schema: "loopwire.release-assets.v1",
  release: { tag: "v0.1.0", version: "0.1.0", gitHead: "e".repeat(40) },
  artifacts: [
    { name: packageName, kind: "native-rpm", target: "opensuse-tumbleweed", architecture: "x86_64",
      bytes: 123, sha256: sourceSha256 },
    { name: "loopwire-linux-x86_64.tar.gz", kind: "portable-archive", target: "linux-generic", architecture: "x86_64",
      bytes: 456, sha256: "d".repeat(64) },
  ],
};
const releaseExpected = { version: "0.1.0", rpmName: packageName, rpmBytes: 123, rpmSha256: sourceSha256,
  tarBytes: 456, tarSha256: "d".repeat(64) };
const zypperXml = `<?xml version='1.0'?><stream><search-result><solvable-list><solvable status="installed" name="loopwire" kind="package" edition="${baseline}" arch="x86_64" repository="Loopwire for openSUSE Tumbleweed - x86_64"/></solvable-list></search-result></stream>\n`;
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
    "package-metadata.tsv": `loopwire\t${baseline}\tx86_64\t(none)\n`,
    "zypper-origin.tsv": `loopwire\t${baseline}\tx86_64\tLoopwire for openSUSE Tumbleweed - x86_64\t(none)\n`,
    "zypper-search.xml": zypperXml,
    "zypper-info.txt": `Information for package loopwire:\nRepository : loopwire\nName : loopwire\nVersion : ${baseline}\nArch : x86_64\nVendor : (none)\nInstalled : Yes\n`,
    "package-files.txt": `${Object.keys(expectedHashes).join("\n")}\n`,
    "installed-files.sha256": `${Object.entries(expectedHashes).map(([name, hash]) => `${hash}  ${name}`).join("\n")}\n`,
    "signed-package.sha256": `${packageSha256}  ${packageName}\n`, "rpm-signature.txt": signature,
    "background-help.txt": "Usage: Loopwire background restore\n", "dsp-provider-help.txt": "Usage: Loopwire DSP provider\n",
    "jack-provider-help.txt": "Usage: Loopwire JACK provider\n", "detect-audio.json": "{\"backends\":[]}\n",
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
  await test("rollback remaining upgraded rejected", () => assert.throws(() => verifyLifecycle(
    transitions.replace(`rollback\t${baseline}`, `rollback\t${upgrade}`), baseline, upgrade), /lifecycle transitions/));
  await test("fabricated lifecycle pass rejected", () => assert.throws(() => verifyLifecycle("pass", baseline, upgrade), /lifecycle transitions/));
  await test("selected target manifest row accepted", () => assert.deepEqual(targetManifestRow(
    `# header\nopensuse-tumbleweed\topenSUSE Tumbleweed\topensuse-tumbleweed\trpm\thttps://example.invalid/image\tsha256\t${"a".repeat(64)}\t2264\tbios\n`,
    "opensuse-tumbleweed"), ["opensuse-tumbleweed", "openSUSE Tumbleweed", "opensuse-tumbleweed", "rpm",
    "https://example.invalid/image", "sha256", "a".repeat(64), "2264", "bios"]));
  await test("duplicate or malformed target manifest rows rejected", () => {
    const row = `opensuse-tumbleweed\topenSUSE Tumbleweed\topensuse-tumbleweed\trpm\thttps://example.invalid/image\tsha256\t${"a".repeat(64)}\t2264\tbios`;
    assert.throws(() => targetManifestRow(`${row}\n${row}\n`, "opensuse-tumbleweed"), /missing or duplicate/);
    assert.throws(() => targetManifestRow(`${row}\textra\n`, "opensuse-tumbleweed"), /nine nonempty fields/);
  });
  await test("duplicate installed hash rejected", () => assert.throws(() => parseInstalledHashes(
    `${"a".repeat(64)}  /usr/bin/loopwire\n${"b".repeat(64)}  /usr/bin/loopwire\n`), /duplicate/));
  await test("selective public release checksums accepted", () => assert.equal(parseReleaseChecksums(
    `${sourceSha256}  ${packageName}\n${"d".repeat(64)}  loopwire-linux-x86_64.tar.gz\n`).get(packageName), sourceSha256));
  await test("duplicate public release checksum rejected", () => assert.throws(() => parseReleaseChecksums(
    `${sourceSha256}  ${packageName}\n${sourceSha256}  ${packageName}\n`), /duplicate/));
  await test("valid release signature accepted and changed manifest rejected", async () => {
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
  await test("exact openSUSE release manifest accepted", () => verifyReleaseAssetManifest(
    JSON.stringify(releaseManifest), releaseExpected));
  await test("wrong release manifest target rejected", () => assert.throws(() => verifyReleaseAssetManifest(
    JSON.stringify({ ...releaseManifest, artifacts: releaseManifest.artifacts.map((entry, index) => index ? entry : { ...entry, target: "fedora-44" }) }),
    releaseExpected), /artifact count/));
  await test("wrong release manifest hash rejected", () => assert.throws(() => verifyReleaseAssetManifest(
    JSON.stringify({ ...releaseManifest, artifacts: releaseManifest.artifacts.map((entry, index) => index ? entry : { ...entry, sha256: "0".repeat(64) }) }),
    releaseExpected), /openSUSE release artifact/));
  await test("wrong release manifest version rejected", () => assert.throws(() => verifyReleaseAssetManifest(
    JSON.stringify({ ...releaseManifest, release: { ...releaseManifest.release, version: "0.2.0" } }), releaseExpected), /public release version/));
  const releaseText = "name=loopwire\nversion=0.1.0\narch=x86_64\nsource_date_epoch=1788115521\n";
  await test("portable RELEASE accepted", () => parsePayloadRelease(releaseText, "0.1.0"));
  await test("wrong portable RELEASE rejected", () => assert.throws(() => parsePayloadRelease(
    releaseText.replace("version=0.1.0", "version=0.2.0"), "0.1.0"), /RELEASE version/));
  await test("exact Zypper origin accepted", () => verifyZypperSearch(zypperXml, baseline));
  await test("wrong Zypper repository rejected", () => assert.throws(() => verifyZypperSearch(
    zypperXml.replace('repository="Loopwire for openSUSE Tumbleweed - x86_64"', 'repository="@System"'), baseline),
  /Zypper repository/));
  await test("valid RPM signature accepted", () => verifyRpmSignature(signature, fingerprint, packageName));
  await test("unsigned RPM rejected", () => assert.throws(() => verifyRpmSignature(
    `${packageName}: digests OK\n`, fingerprint, packageName), /lacks/));
  const packageEntry = { name: "loopwire", version: "0.1.0", release: "1", architecture: "x86_64",
    path: `packages/${packageName}`, sourceReleaseSha256: sourceSha256, sourceRevision: "e".repeat(40),
    distributedSha256: packageSha256, size: 123 };
  await test("exact repository package accepted", () => verifyPackageEntry(packageEntry,
    { version: "0.1.0", name: packageName, sourceRevision: "e".repeat(40) }, packageSha256, sourceSha256, "fixture"));
  await test("public baseline source substitution rejected", () => assert.throws(() => verifyPackageEntry(
    { ...packageEntry, sourceReleaseSha256: "d".repeat(64) }, { version: "0.1.0", name: packageName, sourceRevision: "e".repeat(40) },
    packageSha256, sourceSha256, "fixture"), /source release hash/));
  await test("public source revision substitution rejected", () => assert.throws(() => verifyPackageEntry(
    { ...packageEntry, sourceRevision: "f".repeat(40) },
    { version: "0.1.0", name: packageName, sourceRevision: "e".repeat(40) },
    packageSha256, sourceSha256, "fixture"), /public source revision/));
  await test("distributed package substitution rejected", () => assert.throws(() => verifyPackageEntry(
    { ...packageEntry, distributedSha256: "d".repeat(64) },
    { version: "0.1.0", name: packageName, sourceRevision: "e".repeat(40) },
    packageSha256, sourceSha256, "fixture"), /distributed RPM hash/));

  await stageFixture();
  await test("complete installed stage accepted", verifyStage);
  for (const [name, file, mutation, pattern] of [
    ["changed installed bytes rejected", "installed-files.sha256", (value) => value.replace("a".repeat(64), "d".repeat(64)), /signed repository RPM payload/],
    ["wrong installed version rejected", "package-metadata.tsv", (value) => value.replace(baseline, upgrade), /metadata/],
    ["wrong vendor rejected", "package-metadata.tsv", (value) => value.replace("(none)", "Example Vendor"), /vendor/],
    ["local package origin rejected", "zypper-origin.tsv", (value) => value.replace("\tLoopwire for openSUSE Tumbleweed - x86_64\t(none)", "\t@System\t(none)"), /origin/],
    ["wrong Zypper XML origin rejected", "zypper-search.xml", (value) => value.replace('repository="Loopwire for openSUSE Tumbleweed - x86_64"', 'repository="other"'), /Zypper repository/],
    ["wrong signed RPM digest rejected", "signed-package.sha256", (value) => value.replace(packageSha256, "d".repeat(64)), /signed RPM digest/],
    ["failed RPM signature rejected", "rpm-signature.txt", (value) => value.replace(": OK", ": NOKEY"), /signature verification failed/],
    ["unresolved GUI dependency rejected", "gui-ldd.txt", (value) => `${value}libmissing.so => not found\n`, /linkage/],
    ["unrelated X11 window rejected", "gui-window-names.txt", () => "xterm\n", /application window/],
    ["failed GUI launch rejected", "gui-launch-status.txt", () => "124\n", /GUI launch/],
    ["GUI panic rejected", "gui-launch.log", () => "thread main panicked\n", /fatal GUI log/],
    ["empty provider output rejected", "dsp-provider-help.txt", () => "", /empty evidence/],
    ["missing helper rejected", "package-files.txt", (value) => value.replace("/usr/bin/loopwire-dsp-provider\n", ""), /missing/],
  ]) {
    await stageFixture();
    await change(file, mutation);
    await test(name, () => assert.rejects(verifyStage, pattern));
  }
  console.log(`openSUSE VM proof verifier tests passed: ${passed}`);
} finally {
  await rm(directory, { recursive: true, force: true });
}
