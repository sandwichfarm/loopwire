#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { lstat, mkdtemp, readFile, readdir, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const requiredPaths = [
  "/usr/bin/loopwire", "/usr/bin/loopwire-dsp-provider", "/usr/bin/loopwire-jack-ports",
  "/usr/bin/loopwire-detect-audio", "/usr/lib/loopwire/loopwire-gui",
  "/usr/share/applications/loopwire.desktop", "/usr/share/icons/hicolor/scalable/apps/loopwire.svg",
];

function requireThat(condition, message) {
  if (!condition) throw new Error(message);
}
async function bytes(directory, name) {
  const file = path.join(directory, name);
  const stat = await lstat(file);
  requireThat(stat.isFile() && !stat.isSymbolicLink(), `evidence must be a regular file: ${name}`);
  return readFile(file);
}
async function text(directory, name, nonempty = true) {
  const result = (await bytes(directory, name)).toString("utf8");
  requireThat(!nonempty || result.trim(), `empty evidence: ${name}`);
  return result;
}
function tsvMap(value, label) {
  const map = new Map();
  for (const line of value.trimEnd().split("\n")) {
    const separator = line.indexOf("\t");
    requireThat(separator > 0, `${label} must contain key/value TSV`);
    const key = line.slice(0, separator);
    requireThat(!map.has(key), `${label} repeats ${key}`);
    map.set(key, line.slice(separator + 1));
  }
  return map;
}
function stageTable(value, label) {
  const result = new Map();
  for (const line of value.trimEnd().split("\n")) {
    const fields = line.split("\t");
    requireThat(fields.length === 3 && ["baseline", "upgraded"].includes(fields[0]), `invalid ${label} row`);
    requireThat(!result.has(fields[0]), `${label} repeats ${fields[0]}`);
    requireThat(/^loopwire-[0-9A-Za-z.+~_-]+-1\.fc44\.x86_64\.rpm$/.test(fields[1]), `invalid ${label} package name`);
    requireThat(/^[a-f0-9]{64}$/.test(fields[2]), `invalid ${label} SHA-256`);
    result.set(fields[0], { name: fields[1], sha256: fields[2] });
  }
  requireThat(result.size === 2, `${label} must contain baseline and upgraded rows`);
  return result;
}
function equal(actual, expected, label) {
  requireThat(actual === expected, `${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
function command(program, args) {
  const result = spawnSync(program, args, { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  requireThat(!result.error && result.status === 0,
    `${program} verification failed: ${result.error?.message ?? result.stderr ?? result.stdout}`);
  return result.stdout;
}
function sha256(buffer) { return createHash("sha256").update(buffer).digest("hex"); }

export function parseReleaseChecksums(value) {
  const entries = new Map();
  for (const [index, line] of value.trimEnd().split("\n").entries()) {
    const match = /^([a-f0-9]{64}) {2}([^/\\\s]+)$/.exec(line);
    requireThat(match && !entries.has(match[2]), `invalid or duplicate signed checksum entry at line ${index + 1}`);
    entries.set(match[2], match[1]);
  }
  return entries;
}

export function verifyReleaseSignature(checksumsFile, signatureFile, publicKeyFile) {
  command("openssl", ["dgst", "-sha256", "-verify", publicKeyFile, "-signature", signatureFile, checksumsFile]);
}

export function verifyReleaseAssetManifest(value, expected) {
  const manifest = JSON.parse(value);
  assert.deepEqual(Object.keys(manifest).sort(), ["artifacts", "release", "schema"], "release manifest fields");
  equal(manifest.schema, "loopwire.release-assets.v1", "release manifest schema");
  assert.deepEqual(Object.keys(manifest.release).sort(), ["gitHead", "tag", "version"], "release identity fields");
  equal(manifest.release.tag, `v${expected.version}`, "public release tag");
  equal(manifest.release.version, expected.version, "public release version");
  requireThat(/^[a-f0-9]{40}$/.test(manifest.release.gitHead), "public release commit must be a full lowercase hash");
  requireThat(Array.isArray(manifest.artifacts), "release artifacts must be an array");
  const fedora = manifest.artifacts.filter((entry) => entry && entry.target === "fedora-44");
  equal(fedora.length, 1, "Fedora release artifact count");
  assert.deepEqual(Object.keys(fedora[0]).sort(), ["architecture", "bytes", "kind", "name", "sha256", "target"],
    "Fedora release artifact fields");
  assert.deepEqual(fedora[0], { name: expected.rpmName, kind: "native-rpm", target: "fedora-44",
    architecture: "x86_64", bytes: expected.rpmBytes, sha256: expected.rpmSha256 }, "Fedora release artifact");
  const portable = manifest.artifacts.filter((entry) => entry?.name === "loopwire-linux-x86_64.tar.gz");
  equal(portable.length, 1, "x86_64 portable release artifact count");
  for (const [key, wanted] of Object.entries({ kind: "portable-archive", target: "linux-generic", architecture: "x86_64",
    bytes: expected.tarBytes, sha256: expected.tarSha256 })) equal(portable[0][key], wanted, `portable release artifact ${key}`);
  return manifest;
}

export function parsePayloadRelease(value, expectedVersion) {
  const fields = new Map();
  for (const line of value.trimEnd().split("\n")) {
    const separator = line.indexOf("=");
    requireThat(separator > 0, "invalid RELEASE field");
    const key = line.slice(0, separator);
    requireThat(!fields.has(key), `duplicate RELEASE field: ${key}`);
    fields.set(key, line.slice(separator + 1));
  }
  assert.deepEqual([...fields.keys()].sort(), ["arch", "name", "source_date_epoch", "version"], "RELEASE fields");
  equal(fields.get("name"), "loopwire", "RELEASE name");
  equal(fields.get("version"), expectedVersion, "RELEASE version");
  equal(fields.get("arch"), "x86_64", "RELEASE architecture");
  requireThat(/^[0-9]+$/.test(fields.get("source_date_epoch") ?? ""), "RELEASE source date epoch");
  return fields;
}

export function parseInstalledHashes(value) {
  const result = {};
  for (const line of value.trimEnd().split("\n")) {
    const match = /^([a-f0-9]{64}) {2}(\/usr\/[^\r\n]+)$/.exec(line);
    requireThat(match && !match[2].split("/").includes(".."), "invalid installed-file checksum record");
    requireThat(!Object.hasOwn(result, match[2]), `duplicate installed path: ${match[2]}`);
    result[match[2]] = match[1];
  }
  return result;
}

export function verifyRpmSignature(value, fingerprint, packageName) {
  requireThat(value.includes(packageName), "RPM signature output names the wrong package");
  requireThat(!/NOT OK|NOKEY|NOTTRUSTED|BAD|FAILED|UNSIGNED/i.test(value), "RPM signature verification failed");
  const normalized = value.toLowerCase();
  const fullFingerprint = fingerprint.toLowerCase();
  const keyId = fingerprint.slice(-16).toLowerCase();
  const shortKeyId = fingerprint.slice(-8).toLowerCase();
  requireThat(/(?:OpenPGP[^\n]* )?RSA\/SHA(?:256|512) signature/i.test(value),
    "RPM lacks an RSA OpenPGP signature");
  requireThat(normalized.includes(`key fingerprint: ${fullFingerprint}`) ||
    normalized.includes(`key id ${keyId}`) || normalized.includes(`key id ${shortKeyId}`),
    "RPM signature uses the wrong key");
  requireThat(/Signature[^\n]*:\s*OK/i.test(value), "RPM signature was not accepted");
}

export async function rpmPayload(packageFile) {
  const bsdtar = spawnSync("bsdtar", ["--version"], { encoding: "utf8" });
  if (!bsdtar.error && bsdtar.status === 0) {
    const listed = command("bsdtar", ["-tf", packageFile]).trimEnd().split("\n");
    for (const name of listed) {
      const normalized = name.replace(/^\.\//, "");
      requireThat(normalized.startsWith("usr/") && !normalized.split("/").includes(".."), "unsafe RPM payload path");
    }
    const temporary = await mkdtemp(path.join(tmpdir(), "loopwire-rpm-payload-"));
    try {
      command("bsdtar", ["--no-same-owner", "--no-same-permissions", "-xf", packageFile, "-C", temporary]);
      const files = {};
      async function collect(directory) {
        for (const entry of await readdir(directory, { withFileTypes: true })) {
          const item = path.join(directory, entry.name);
          if (entry.isDirectory()) {
            await collect(item);
            continue;
          }
          if (!entry.isFile() && !entry.isSymbolicLink()) continue;
          const resolved = await realpath(item);
          requireThat(resolved.startsWith(`${temporary}${path.sep}`), "RPM payload link escapes extraction root");
          if (!(await lstat(resolved)).isFile()) continue;
          const installed = `/${path.relative(temporary, item).split(path.sep).join("/")}`;
          requireThat(!Object.hasOwn(files, installed), `duplicate RPM payload path: ${installed}`);
          files[installed] = sha256(await readFile(item));
        }
      }
      await collect(path.join(temporary, "usr"));
      return files;
    } finally {
      await rm(temporary, { recursive: true, force: true });
    }
  }
  const mount = path.dirname(packageFile);
  return JSON.parse(command("bash", [path.join(repositoryRoot, "scripts/with-rpm-tools.sh"),
    "--read-only-path", mount, "python3", "-c", String.raw`
import hashlib, json, pathlib, subprocess, sys, tempfile
package = pathlib.Path(sys.argv[1])
listed = subprocess.run(['rpm', '-qlp', str(package)], check=True, capture_output=True, text=True).stdout.splitlines()
for name in listed:
    pure = pathlib.PurePosixPath(name)
    assert pure.is_absolute() and pure.parts[:2] == ('/', 'usr') and '..' not in pure.parts, 'unsafe package path'
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    first = subprocess.Popen(['rpm2cpio', str(package)], stdout=subprocess.PIPE)
    extracted = subprocess.run(['cpio', '--quiet', '-idm', '--no-absolute-filenames'], cwd=root,
                               stdin=first.stdout, capture_output=True, text=False)
    first.stdout.close()
    assert first.wait() == 0 and extracted.returncode == 0, extracted.stderr.decode(errors='replace')
    files = {}
    for name in listed:
        item = root / name.lstrip('/')
        if not item.is_file():
            continue
        resolved = item.resolve(strict=True)
        assert resolved.is_relative_to(root), 'package link escapes extraction root'
        assert name not in files, 'duplicate package path'
        files[name] = hashlib.sha256(item.read_bytes()).hexdigest()
    print(json.dumps(files, sort_keys=True))
`, packageFile]));
}

export function verifyLifecycle(value, baselineVersion, upgradeVersion) {
  equal(value.trimEnd(), [
    `install\t${baselineVersion}\tinstalled`, `reinstall\t${baselineVersion}\tinstalled`,
    `upgrade\t${upgradeVersion}\tinstalled`, `rollback\t${baselineVersion}\tinstalled`,
    `remove\t${baselineVersion}\tabsent`,
  ].join("\n"), "lifecycle transitions");
}

export function verifyPackageEntry(entry, expected, packageSha256, sourceSha256, label) {
  requireThat(entry && typeof entry === "object" && !Array.isArray(entry), `${label} package entry missing`);
  equal(entry.name, "loopwire", `${label} package name`);
  equal(entry.version, expected.version, `${label} package version`);
  equal(entry.release, "1.fc44", `${label} package release`);
  equal(entry.architecture, "x86_64", `${label} package architecture`);
  equal(entry.path, `packages/${expected.name}`, `${label} package path`);
  equal(entry.sourceReleaseSha256, sourceSha256, `${label} source release hash`);
  equal(entry.distributedSha256, packageSha256, `${label} distributed RPM hash`);
  requireThat(Number.isSafeInteger(entry.size) && entry.size > 0, `${label} package size missing`);
}

export async function verifyInstalledStage(directory, stage, version, fingerprint, packageName, packageSha256, payloadHashes) {
  const prefix = `${stage}/`;
  equal((await text(directory, `${prefix}package-metadata.tsv`)).trim(),
    `loopwire\t${version}\tx86_64`, `${stage} package metadata`);
  equal((await text(directory, `${prefix}dnf-origin.txt`)).trim(),
    `loopwire|${version}|x86_64|loopwire`, `${stage} repository origin`);
  const info = await text(directory, `${prefix}dnf-info.txt`);
  requireThat(/^From repository\s*:\s*loopwire$/m.test(info), `${stage} lacks DNF repository origin`);
  const files = (await text(directory, `${prefix}package-files.txt`)).trim().split("\n");
  for (const installed of requiredPaths) requireThat(files.includes(installed), `${stage} missing ${installed}`);
  const hashes = parseInstalledHashes(await text(directory, `${prefix}installed-files.sha256`));
  assert.deepEqual(hashes, payloadHashes, `${stage} installed bytes must equal the signed repository RPM payload`);
  equal((await text(directory, `${prefix}signed-package.sha256`)).trim(), `${packageSha256}  ${packageName}`,
    `${stage} signed RPM digest`);
  verifyRpmSignature(await text(directory, `${prefix}rpm-signature.txt`), fingerprint, packageName);
  for (const help of ["background-help.txt", "dsp-provider-help.txt", "jack-provider-help.txt"]) {
    await text(directory, `${prefix}${help}`);
  }
  const detection = JSON.parse(await text(directory, `${prefix}detect-audio.json`));
  requireThat(detection && typeof detection === "object", `${stage} detection must be JSON object/array`);
  const linkage = await text(directory, `${prefix}gui-ldd.txt`);
  requireThat(!linkage.includes("not found") && /libgtk-3/.test(linkage) && /libwebkit2gtk/.test(linkage),
    `${stage} GUI linkage missing or unresolved`);
  equal((await text(directory, `${prefix}gui-launch-status.txt`)).trim(), "0", `${stage} GUI launch`);
  requireThat(/^\d+(?:\n\d+)*\n?$/.test(await text(directory, `${prefix}gui-window-ids.txt`)), `${stage} lacks X11 window ids`);
  const names = (await text(directory, `${prefix}gui-window-names.txt`)).trim().split("\n");
  requireThat(names.every((name) => /^(Loopwire|loopwire-gui)$/.test(name)), `${stage} lacks Loopwire application window`);
  const launch = await text(directory, `${prefix}gui-launch.log`, false);
  requireThat(!/error while loading shared libraries|panic|protocol error|missing acquire timeline/i.test(launch), `${stage} fatal GUI log`);
  await text(directory, `${prefix}xvfb.log`, false);
}

export async function verifyEvidence({ target, evidenceDir, gitHead }) {
  equal(target, "fedora-44", "supported target");
  requireThat(/^[a-f0-9]{40}$/.test(gitHead ?? ""), "--git-head must be a full lowercase commit hash");
  const summary = tsvMap(await text(evidenceDir, "summary.tsv"), "summary");
  equal(summary.get("schema"), "loopwire.fedora-repository-vm-proof.v1", "schema");
  equal(summary.get("target"), target, "target");
  equal(summary.get("git_head"), gitHead, "summary commit");
  equal((await text(evidenceDir, "git-head.txt")).trim(), gitHead, "evidence commit");
  equal(summary.get("payload_kind"), "public-release-baseline-with-synthetic-upgrade", "payload provenance kind");
  equal(summary.get("synthetic_upgrade"), "true", "synthetic fixture disclosure");
  const version = summary.get("version");
  requireThat(/^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\+[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?$/.test(version ?? ""), "invalid baseline version");
  const upgradedVersion = `${version}${version.includes("+") ? "." : "+"}dnffixture1`;
  equal(summary.get("upgrade_version"), upgradedVersion, "synthetic fixture version");
  const baselineVersion = `${version}-1.fc44`;
  const upgradeVersion = `${upgradedVersion}-1.fc44`;
  equal(summary.get("baseline_package_version"), baselineVersion, "baseline package version");
  equal(summary.get("upgrade_package_version"), upgradeVersion, "upgrade package version");
  const fingerprint = summary.get("fingerprint");
  requireThat(/^[A-F0-9]{40}$/.test(fingerprint ?? ""), "invalid signing fingerprint");
  const baseUrl = summary.get("base_url");
  equal(baseUrl, "https://127.0.0.1:8444/fedora/44/x86_64", "guest-only HTTPS origin");
  const epoch = summary.get("verification_epoch");
  requireThat(/^[0-9]{10}$/.test(epoch ?? "") && Number(epoch) <= Date.now() / 1000 + 300, "invalid proof timestamp");
  const os = new Map((await text(evidenceDir, "os-release")).split("\n").filter((line) => /^[A-Z_]+=/.test(line)).map((line) => {
    const separator = line.indexOf("=");
    return [line.slice(0, separator), line.slice(separator + 1).replace(/^"|"$/g, "")];
  }));
  equal(os.get("ID"), "fedora", "guest OS");
  equal(os.get("VERSION_ID"), "44", "guest OS version");
  requireThat(["kvm", "qemu"].includes((await text(evidenceDir, "virtualization.txt")).trim()), "not a VM proof");
  requireThat((await text(evidenceDir, "uname.txt")).includes("Linux"), "guest kernel evidence missing");
  await text(evidenceDir, "console.log");
  const targetRows = (await readFile(path.join(repositoryRoot, "packaging/vm/native-package-targets.tsv"), "utf8"))
    .split("\n").map((line) => line.split("\t")).filter((row) => row[0] === target);
  requireThat(targetRows.length === 1, "target missing or duplicate in image manifest");
  const row = targetRows[0];
  const image = tsvMap(await text(evidenceDir, "image.tsv"), "image");
  for (const [key, expected] of Object.entries({ schema: "loopwire.native-package-image.v1", target,
    distro: row[1], url: row[4], checksum_algorithm: row[5], checksum: row[6], actual_checksum: row[6], firmware: row[8] })) {
    equal(image.get(key), expected, `image ${key}`);
  }
  equal((await text(evidenceDir, "initial-package-status.txt")).trim(), "absent", "clean guest status");
  requireThat(/^[a-f0-9]{64} {2}loopwire-linux-x86_64\.tar\.gz\n?$/.test(await text(evidenceDir, "release-payload.sha256")),
    "missing original payload digest");
  const publicDirectory = path.join(evidenceDir, "public-release");
  const publicInventory = (await readdir(publicDirectory)).sort();
  assert.deepEqual(publicInventory, ["RELEASE", "SHA256SUMS", "SHA256SUMS.sig",
    `loopwire-${baselineVersion}.x86_64.rpm`, "loopwire-linux-x86_64.tar.gz", "release-assets.json",
    "release-signing-public.pem"].sort(), "public release evidence inventory");
  equal(await text(publicDirectory, "release-signing-public.pem"),
    await readFile(path.join(repositoryRoot, "packaging/release-signing-public.pem"), "utf8"), "committed release signing key");
  verifyReleaseSignature(path.join(publicDirectory, "SHA256SUMS"), path.join(publicDirectory, "SHA256SUMS.sig"),
    path.join(repositoryRoot, "packaging/release-signing-public.pem"));
  const releaseChecksums = parseReleaseChecksums(await text(publicDirectory, "SHA256SUMS"));
  const publicRpmName = `loopwire-${baselineVersion}.x86_64.rpm`;
  const publicRpm = await bytes(publicDirectory, publicRpmName);
  const publicTar = await bytes(publicDirectory, "loopwire-linux-x86_64.tar.gz");
  const publicManifest = await bytes(publicDirectory, "release-assets.json");
  for (const [name, content] of [[publicRpmName, publicRpm], ["loopwire-linux-x86_64.tar.gz", publicTar],
    ["release-assets.json", publicManifest]]) {
    requireThat(releaseChecksums.has(name), `signed checksums lack ${name}`);
    equal(releaseChecksums.get(name), sha256(content), `signed public release hash for ${name}`);
  }
  const releaseManifest = verifyReleaseAssetManifest(publicManifest.toString("utf8"), {
    version, rpmName: publicRpmName, rpmBytes: publicRpm.length, rpmSha256: sha256(publicRpm),
    tarBytes: publicTar.length, tarSha256: sha256(publicTar),
  });
  parsePayloadRelease(await text(publicDirectory, "RELEASE"), version);
  equal(await text(evidenceDir, "payload-release.txt"), await text(publicDirectory, "RELEASE"), "captured RELEASE data");
  equal(summary.get("public_release_git_head"), releaseManifest.release.gitHead, "summary public release commit");
  equal((await text(evidenceDir, "public-release-git-head.txt")).trim(), releaseManifest.release.gitHead,
    "captured public release commit");

  const source = await text(evidenceDir, "loopwire.repo");
  for (const line of ["[loopwire]", `baseurl=${baseUrl}`, "enabled=1", "gpgcheck=1", "repo_gpgcheck=1", "sslverify=1",
    `gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-loopwire-${fingerprint}`]) {
    requireThat(source.split("\n").includes(line), `DNF source lacks ${line}`);
  }
  requireThat(!/sslverify\s*=\s*0|gpgcheck\s*=\s*0|repo_gpgcheck\s*=\s*0|skip_if_unavailable\s*=\s*True/i.test(source),
    "DNF proof bypasses repository authentication or availability failures");
  equal(await text(evidenceDir, "https-key.asc"), await text(evidenceDir, "repository-key.asc"), "HTTPS public key");
  equal(await text(evidenceDir, "configured-repository-key.asc"), await text(evidenceDir, "repository-key.asc"), "configured public key");
  command("openssl", ["verify", "-attime", epoch, "-CAfile", path.join(evidenceDir, "tls-ca.crt"),
    "-verify_ip", "127.0.0.1", path.join(evidenceDir, "tls-server.crt")]);

  const sources = stageTable(await text(evidenceDir, "release-sources.tsv"), "release sources");
  const signed = stageTable(await text(evidenceDir, "signed-packages.tsv"), "signed packages");
  const expectedNames = {
    baseline: `loopwire-${baselineVersion}.x86_64.rpm`,
    upgraded: `loopwire-${upgradeVersion}.x86_64.rpm`,
  };
  equal(sources.get("baseline").sha256, sha256(publicRpm), "baseline source must be the public release RPM");
  equal(summary.get("baseline_source_sha256"), sha256(publicRpm), "summary public baseline source hash");
  for (const stage of ["baseline", "upgraded"]) {
    equal(sources.get(stage).name, expectedNames[stage], `${stage} source RPM name`);
    equal(signed.get(stage).name, expectedNames[stage], `${stage} signed RPM name`);
    equal(summary.get(`${stage === "upgraded" ? "upgrade" : stage}_source_sha256`), sources.get(stage).sha256,
      `${stage} summary source hash`);
    equal(summary.get(`${stage === "upgraded" ? "upgrade" : stage}_rpm_sha256`), signed.get(stage).sha256,
      `${stage} summary signed hash`);
    equal(sha256(await bytes(evidenceDir, `packages/${expectedNames[stage]}`)), signed.get(stage).sha256,
      `${stage} signed RPM evidence hash`);
  }
  const packageNames = (await readdir(path.join(evidenceDir, "packages"))).sort();
  assert.deepEqual(packageNames, ["baseline-rpm-signature.txt", expectedNames.baseline,
    expectedNames.upgraded, "upgraded-rpm-signature.txt"].sort(), "package evidence inventory");
  verifyRpmSignature(await text(evidenceDir, "packages/baseline-rpm-signature.txt"), fingerprint, expectedNames.baseline);
  verifyRpmSignature(await text(evidenceDir, "packages/upgraded-rpm-signature.txt"), fingerprint, expectedNames.upgraded);
  const payloadHashes = {
    [baselineVersion]: await rpmPayload(path.join(evidenceDir, "packages", expectedNames.baseline)),
    [upgradeVersion]: await rpmPayload(path.join(evidenceDir, "packages", expectedNames.upgraded)),
  };
  assert.deepEqual(await rpmPayload(path.join(publicDirectory, publicRpmName)), payloadHashes[baselineVersion],
    "repository signing must preserve the public release RPM payload");

  for (const stage of ["initial", "upgraded", "rolled-back"]) {
    const directory = path.join(evidenceDir, "repositories", stage);
    const result = command("bash", [path.join(repositoryRoot, "scripts/with-rpm-tools.sh"), "--read-only-path", evidenceDir,
      "python3", path.join(repositoryRoot, "scripts/rpm-repository.py"), "verify", "--repository", directory,
      "--public-key", path.join(evidenceDir, "repository-key.asc"), "--fingerprint", fingerprint, "--now", epoch]);
    JSON.parse(result);
    JSON.parse(await text(evidenceDir, `repositories/${stage}-verification.json`));
    const manifest = JSON.parse(await text(directory, "repository-manifest.json"));
    equal(manifest.schema, "loopwire.rpm-repository.v1", `${stage} repository schema`);
    equal(manifest.schemaVersion, 1, `${stage} repository schema version`);
    assert.deepEqual(manifest.target, { distribution: "fedora", release: "44", architecture: "x86_64" },
      `${stage} repository target`);
    const served = JSON.parse(await text(evidenceDir, `repositories/${stage}-public-verification.json`));
    equal(served.status, "verified", `${stage} HTTPS verification`);
    equal(served.revision, manifest.revision, `${stage} HTTPS revision`);
    equal(served.files, manifest.files.length + 1, `${stage} HTTPS file count including manifest`);
    const expectedVersions = stage === "upgraded" ? [baselineVersion, upgradeVersion] : [baselineVersion];
    equal(manifest.packages.length, expectedVersions.length, `${stage} package count`);
    for (const expectedVersion of expectedVersions) {
      const fixtureStage = expectedVersion === baselineVersion ? "baseline" : "upgraded";
      const matches = manifest.packages.filter((entry) => entry.name === "loopwire" &&
        `${entry.version}-${entry.release}` === expectedVersion);
      requireThat(matches.length === 1, `${stage} must contain exactly one ${expectedVersion} package`);
      verifyPackageEntry(matches[0], { version: expectedVersion.replace(/-1\.fc44$/, ""), name: expectedNames[fixtureStage] },
        signed.get(fixtureStage).sha256, sources.get(fixtureStage).sha256, `${stage} ${expectedVersion}`);
    }
    if (stage !== "upgraded") requireThat(!manifest.packages.some((entry) => entry.version === upgradedVersion),
      `${stage} unexpectedly advertises upgrade`);
  }

  verifyLifecycle(await text(evidenceDir, "lifecycle.tsv"), baselineVersion, upgradeVersion);
  for (const [stage, expectedVersion] of Object.entries({
    install: baselineVersion, reinstall: baselineVersion, upgrade: upgradeVersion, rollback: baselineVersion,
  })) {
    const fixtureStage = expectedVersion === baselineVersion ? "baseline" : "upgraded";
    await verifyInstalledStage(evidenceDir, stage, expectedVersion, fingerprint, expectedNames[fixtureStage],
      signed.get(fixtureStage).sha256, payloadHashes[expectedVersion]);
    const log = await text(evidenceDir, `${stage}.log`);
    requireThat(log.includes("loopwire") && log.includes(expectedVersion), `${stage} lacks DNF operation/version log`);
  }
  const commands = await text(evidenceDir, "commands.log");
  for (const needle of ["dnf install -y loopwire-", "dnf reinstall -y", "dnf upgrade -y loopwire",
    "dnf downgrade -y", "dnf remove -y loopwire", " -Kv ", "smoke_installed", "xdotool"]) {
    requireThat(commands.includes(needle), `missing executed command: ${needle}`);
  }
  for (const file of ["bootstrap.log", "bootstrap-makecache.log", "upgrade-makecache.log", "rollback-makecache.log",
    "remove.log", "source-removal.log", "source-removal-clean.log"]) await text(evidenceDir, file);
  const requests = await text(evidenceDir, "https-server.log");
  for (const requested of [`/fedora/44/x86_64/keys/${fingerprint}.asc`, "/fedora/44/x86_64/repodata/repomd.xml",
    "/fedora/44/x86_64/repodata/repomd.xml.asc", `/fedora/44/x86_64/packages/${expectedNames.baseline}`,
    `/fedora/44/x86_64/packages/${expectedNames.upgraded}`]) {
    requireThat(requests.includes(requested), `missing real HTTPS request: ${requested}`);
  }
  const removal = tsvMap(await text(evidenceDir, "removed-files.tsv"), "removed paths");
  for (const removed of [...requiredPaths.filter((value) => value !== "/usr/lib/loopwire/loopwire-gui"), "/usr/lib/loopwire"]) {
    equal(removal.get(removed), "absent", `removed ${removed}`);
  }
  requireThat(!/(^|\s)loopwire(\s|$)/m.test(await text(evidenceDir, "source-removal-repositories.txt")),
    "removed DNF source remains active");
  return { target, gitHead, baselineVersion, upgradeVersion, fingerprint,
    packageHashes: { [baselineVersion]: signed.get("baseline").sha256, [upgradeVersion]: signed.get("upgraded").sha256 } };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = {};
    for (let index = 2; index < process.argv.length; index += 2) {
      const option = process.argv[index];
      requireThat(["--target", "--evidence-dir", "--git-head"].includes(option) && process.argv[index + 1], `invalid option: ${option}`);
      requireThat(!Object.hasOwn(args, option), `duplicate option: ${option}`);
      args[option] = process.argv[index + 1];
    }
    requireThat(args["--evidence-dir"], "--evidence-dir is required");
    const result = await verifyEvidence({ target: args["--target"], evidenceDir: path.resolve(args["--evidence-dir"]), gitHead: args["--git-head"] });
    console.log(`Fedora repository VM proof verified: ${result.target}`);
    console.log(JSON.stringify(result));
  } catch (error) {
    console.error(`verify-fedora-repository-vm-proof: ${error.message}`);
    process.exitCode = 1;
  }
}
