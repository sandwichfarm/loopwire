#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { lstat, readFile, readdir } from "node:fs/promises";
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
function equal(actual, expected, label) {
  requireThat(actual === expected, `${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
function command(program, args) {
  const result = spawnSync(program, args, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  requireThat(!result.error && result.status === 0,
    `${program} verification failed: ${result.error?.message ?? result.stderr ?? result.stdout}`);
  return result.stdout;
}
function sha256(buffer) { return createHash("sha256").update(buffer).digest("hex"); }

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

export function debPayload(packageFile) {
  // Read the signed .deb payload without extracting or executing package content.
  return JSON.parse(command("python3", ["-c", `
import hashlib, io, json, pathlib, sys, tarfile
raw = pathlib.Path(sys.argv[1]).read_bytes()
assert raw[:8] == b'!<arch>\\n', 'invalid deb archive'
position = 8
payload = None
while position < len(raw):
    header = raw[position:position + 60]
    assert len(header) == 60 and header[58:60] == b'\\x60\\n', 'invalid ar header'
    size = int(header[48:58].decode().strip())
    assert size >= 0 and position + 60 + size <= len(raw), 'truncated ar member'
    name = header[:16].decode().strip().rstrip('/')
    content = raw[position + 60:position + 60 + size]
    if name.startswith('data.tar'):
        assert payload is None, 'multiple package payloads'
        payload = content
    position += 60 + size + size % 2
assert payload is not None, 'missing package payload'
files = {}
with tarfile.open(fileobj=io.BytesIO(payload), mode='r:*') as archive:
    for member in archive:
        if not member.isfile():
            continue
        relative = pathlib.PurePosixPath(member.name)
        assert not relative.is_absolute() and '..' not in relative.parts, 'unsafe package path'
        name = '/' + str(relative)
        assert name.startswith('/usr/') and name not in files, 'unexpected package path'
        files[name] = hashlib.sha256(archive.extractfile(member).read()).hexdigest()
print(json.dumps(files))
`, packageFile]));
}

export function verifyLifecycle(value, baselineVersion, upgradeVersion) {
  equal(value.trimEnd(), [
    `install\t${baselineVersion}\tinstalled`, `reinstall\t${baselineVersion}\tinstalled`,
    `upgrade\t${upgradeVersion}\tinstalled`, `rollback\t${baselineVersion}\tinstalled`,
    `remove\t${baselineVersion}\tabsent`,
  ].join("\n"), "lifecycle transitions");
}

export async function verifyInstalledStage(directory, stage, version, baseUrl, payloadHashes) {
  const prefix = `${stage}/`;
  equal((await text(directory, `${prefix}package-metadata.tsv`)).trim(),
    `loopwire\t${version}\tamd64\tinstall ok installed`, `${stage} package metadata`);
  const files = (await text(directory, `${prefix}package-files.txt`)).trim().split("\n");
  for (const installed of requiredPaths) requireThat(files.includes(installed), `${stage} missing ${installed}`);
  const hashes = parseInstalledHashes(await text(directory, `${prefix}installed-files.sha256`));
  assert.deepEqual(hashes, payloadHashes, `${stage} installed bytes must equal the signed package payload`);
  const policy = await text(directory, `${prefix}apt-policy.txt`);
  requireThat(policy.includes(baseUrl) && policy.includes(`Installed: ${version}`), `${stage} lacks installed version/repository origin`);
  for (const help of ["background-help.txt", "dsp-provider-help.txt", "jack-provider-help.txt"]) {
    await text(directory, `${prefix}${help}`);
  }
  const detection = JSON.parse(await text(directory, `${prefix}detect-audio.json`));
  requireThat(detection && typeof detection === "object", `${stage} detection must be JSON object/array`);
  const linkage = await text(directory, `${prefix}gui-ldd.txt`);
  requireThat(!linkage.includes("not found") && /libgtk-3/.test(linkage) && /libwebkit2gtk/.test(linkage), `${stage} GUI linkage missing or unresolved`);
  equal((await text(directory, `${prefix}gui-launch-status.txt`)).trim(), "0", `${stage} GUI launch`);
  requireThat(/^\d+(?:\n\d+)*\n?$/.test(await text(directory, `${prefix}gui-window-ids.txt`)), `${stage} lacks X11 window ids`);
  const names = (await text(directory, `${prefix}gui-window-names.txt`)).trim().split("\n");
  requireThat(names.every((name) => /^(Loopwire|loopwire-gui)$/.test(name)), `${stage} lacks Loopwire application window`);
  const launch = await text(directory, `${prefix}gui-launch.log`, false);
  requireThat(!/error while loading shared libraries|panic|protocol error|missing acquire timeline/i.test(launch), `${stage} fatal GUI log`);
  await text(directory, `${prefix}xvfb.log`, false);
}

export async function verifyEvidence({ target, evidenceDir, gitHead }) {
  requireThat(["ubuntu-24.04", "debian-13"].includes(target), "supported --target is required");
  requireThat(/^[a-f0-9]{40}$/.test(gitHead ?? ""), "--git-head must be a full lowercase commit hash");
  const summary = tsvMap(await text(evidenceDir, "summary.tsv"), "summary");
  equal(summary.get("schema"), "loopwire.apt-repository-vm-proof.v1", "schema");
  equal(summary.get("target"), target, "target");
  equal(summary.get("git_head"), gitHead, "summary commit");
  equal((await text(evidenceDir, "git-head.txt")).trim(), gitHead, "evidence commit");
  equal(summary.get("payload_kind"), "cached-release-lifecycle-fixture", "payload provenance kind");
  const version = summary.get("version");
  requireThat(/^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\+[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?$/.test(version ?? ""), "invalid baseline version");
  const upgradedVersion = `${version}${version.includes("+") ? "." : "+"}aptfixture1`;
  equal(summary.get("upgrade_version"), upgradedVersion, "synthetic fixture version");
  const suffix = target === "ubuntu-24.04" ? "1ubuntu24.04" : "1debian13";
  const baselineVersion = `${version}-${suffix}`;
  const upgradeVersion = `${upgradedVersion}-${suffix}`;
  equal(summary.get("baseline_package_version"), baselineVersion, "baseline package version");
  equal(summary.get("upgrade_package_version"), upgradeVersion, "upgrade package version");
  const fingerprint = summary.get("fingerprint");
  requireThat(/^[A-F0-9]{40}$/.test(fingerprint ?? ""), "invalid signing fingerprint");
  const baseUrl = summary.get("base_url");
  equal(baseUrl, "https://127.0.0.1:8443", "guest-only HTTPS origin");
  const epoch = summary.get("verification_epoch");
  requireThat(/^[0-9]{10}$/.test(epoch ?? "") && Number(epoch) <= Date.now() / 1000 + 300, "invalid proof timestamp");
  const os = new Map((await text(evidenceDir, "os-release")).split("\n").filter((line) => /^[A-Z_]+=/.test(line)).map((line) => {
    const separator = line.indexOf("=");
    return [line.slice(0, separator), line.slice(separator + 1).replace(/^"|"$/g, "")];
  }));
  equal(os.get("ID"), target === "ubuntu-24.04" ? "ubuntu" : "debian", "guest OS");
  equal(os.get("VERSION_ID"), target === "ubuntu-24.04" ? "24.04" : "13", "guest OS version");
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
  requireThat(/^[a-f0-9]{64} {2}loopwire-linux-x86_64.tar.gz\n?$/.test(await text(evidenceDir, "release-payload.sha256")), "missing original payload digest");
  await text(evidenceDir, "payload-release.txt");
  const source = await text(evidenceDir, "loopwire.sources");
  for (const line of [`URIs: ${baseUrl}`, `Suites: ${target}`, "Components: main", "Architectures: amd64",
    `Signed-By: /etc/apt/keyrings/loopwire-${fingerprint}.asc`]) requireThat(source.split("\n").includes(line), `APT source lacks ${line}`);
  requireThat(!/Trusted:|Allow-Insecure:/i.test(source), "APT proof bypasses authentication");
  equal(await text(evidenceDir, "https-key.asc"), await text(evidenceDir, "repository-key.asc"), "HTTPS public key");
  command("openssl", ["verify", "-attime", epoch, "-CAfile", path.join(evidenceDir, "tls-ca.crt"),
    "-verify_ip", "127.0.0.1", path.join(evidenceDir, "tls-server.crt")]);

  const packageHashes = {};
  const payloadHashes = {};
  const packageNames = await readdir(path.join(evidenceDir, "packages"));
  equal(packageNames.length, 2, "package evidence count");
  for (const packageVersion of [baselineVersion, upgradeVersion]) {
    const name = `loopwire_${packageVersion}_amd64.deb`;
    requireThat(packageNames.includes(name), `missing package ${name}`);
    packageHashes[packageVersion] = sha256(await bytes(evidenceDir, `packages/${name}`));
    payloadHashes[packageVersion] = debPayload(path.join(evidenceDir, "packages", name));
  }
  for (const stage of ["initial", "upgraded", "rolled-back"]) {
    const directory = path.join(evidenceDir, "repositories", stage);
    const result = command("bash", [path.join(repositoryRoot, "scripts/with-apt-tools.sh"), "--read-only-path", evidenceDir,
      "python3", path.join(repositoryRoot, "scripts/apt-repository.py"), "verify", "--repository", directory,
      "--public-key", path.join(evidenceDir, "repository-key.asc"), "--fingerprint", fingerprint, "--now", epoch]);
    JSON.parse(result);
    JSON.parse(await text(evidenceDir, `repositories/${stage}-verification.json`));
    const snapshot = JSON.parse(await text(directory, "repository-manifest.json"));
    const served = JSON.parse(await text(evidenceDir, `repositories/${stage}-public-verification.json`));
    equal(served.status, "verified", `${stage} HTTPS verification`);
    equal(served.revision, snapshot.revision, `${stage} HTTPS revision`);
    equal(served.files, snapshot.files.length, `${stage} HTTPS file count`);
    const packages = (await text(directory, `dists/${target}/main/binary-amd64/Packages`)).trim().split(/\n\n+/).map((block) => {
      return new Map(block.split("\n").filter((line) => /^[^ :]+:/.test(line)).map((line) => {
        const separator = line.indexOf(":");
        return [line.slice(0, separator), line.slice(separator + 1).trim()];
      }));
    });
    for (const expectedVersion of stage === "upgraded" ? [baselineVersion, upgradeVersion] : [baselineVersion]) {
      const matches = packages.filter((item) => item.get("Package") === "loopwire" && item.get("Version") === expectedVersion);
      requireThat(matches.length === 1, `${stage} must contain exactly one ${expectedVersion} package`);
      equal(matches[0].get("SHA256"), packageHashes[expectedVersion], `${stage} signed package digest`);
      equal(matches[0].get("Architecture"), "amd64", `${stage} signed architecture`);
    }
    if (stage !== "upgraded") requireThat(!packages.some((item) => item.get("Version") === upgradeVersion), `${stage} unexpectedly advertises upgrade`);
  }
  verifyLifecycle(await text(evidenceDir, "lifecycle.tsv"), baselineVersion, upgradeVersion);
  for (const [stage, expectedVersion] of Object.entries({ install: baselineVersion, reinstall: baselineVersion, upgrade: upgradeVersion, rollback: baselineVersion })) {
    await verifyInstalledStage(evidenceDir, stage, expectedVersion, baseUrl, payloadHashes[expectedVersion]);
    const log = await text(evidenceDir, `${stage}.log`);
    requireThat(log.includes("loopwire") && log.includes(expectedVersion), `${stage} lacks APT operation/version log`);
  }
  const commands = await text(evidenceDir, "commands.log");
  for (const needle of ["apt-get install -y loopwire=", "apt-get install --reinstall", "apt-get install --only-upgrade",
    "apt-get install --allow-downgrades", "apt-get remove -y loopwire", "smoke_installed", "xdotool"]) {
    requireThat(commands.includes(needle), `missing executed command: ${needle}`);
  }
  for (const file of ["bootstrap.log", "bootstrap-update.log", "upgrade-update.log", "rollback-update.log", "remove.log", "source-removal.log", "source-removal-update.log"]) {
    await text(evidenceDir, file);
  }
  const requests = await text(evidenceDir, "https-server.log");
  requireThat(requests.includes(`/keys/${fingerprint}.asc`) && requests.includes(`/dists/${target}/InRelease`) && requests.includes(".deb"), "missing real HTTPS key/index/package request evidence");
  const removal = tsvMap(await text(evidenceDir, "removed-files.tsv"), "removed paths");
  for (const removed of [...requiredPaths.filter((value) => value !== "/usr/lib/loopwire/loopwire-gui"), "/usr/lib/loopwire"]) {
    equal(removal.get(removed), "absent", `removed ${removed}`);
  }
  requireThat(!(await text(evidenceDir, "source-removal-policy.txt", false)).includes(baseUrl), "removed APT source remains active");
  return { target, gitHead, baselineVersion, upgradeVersion, fingerprint, packageHashes };
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
    console.log(`APT repository VM proof verified: ${result.target}`);
    console.log(JSON.stringify(result));
  } catch (error) {
    console.error(`verify-apt-repository-vm-proof: ${error.message}`);
    process.exitCode = 1;
  }
}
