#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const verifier = join(repository, "scripts/verify-native-package-proof-snapshot.mjs");
const lockHelper = join(repository, "scripts/ci-impact.rb");
const snapshot = "vm/native-package-proof";
const manifest = "packaging/vm/native-package-targets.tsv";
const targets = readdirSync(join(repository, snapshot)).filter((name) => name !== "README.md");
const recordedCommit = readFileSync(join(repository, snapshot, targets[0], "git-head.txt"), "utf8").trim();
const testedLock = command("git", ["show", `${recordedCommit}:pnpm-lock.yaml`], repository);
const currentLock = readFileSync(join(repository, "pnpm-lock.yaml"), "utf8");
const fixture = mkdtempSync(join(tmpdir(), "loopwire-native-proof-test-"));
let passed = 0;

try {
  git("init", "--quiet");
  git("config", "user.name", "Native proof test");
  git("config", "user.email", "native-proof@example.invalid");
  git("config", "commit.gpgsign", "false");
  write("pnpm-lock.yaml", testedLock);
  write("apps/desktop/src/proof-fixture.ts", "export const value = 1;\n");
  mkdirSync(join(fixture, dirname(manifest)), { recursive: true });
  cpSync(join(repository, manifest), join(fixture, manifest));
  const testedCommit = commit();
  cpSync(join(repository, snapshot), join(fixture, snapshot), { recursive: true });
  setEvidenceCommit(testedCommit);
  const baseline = commit();

  function test(name, action) {
    git("reset", "--hard", baseline);
    git("clean", "-fd");
    action();
    passed += 1;
    console.log(`PASS ${name}`);
  }

  test("unchanged native proof passes", () => verify(true));
  test("real website GSAP lockfile addition preserves native proof", () => {
    write("pnpm-lock.yaml", currentLock);
    commit();
    verify(true);
  });
  test("web-only package integrity changes preserve native proof", () => {
    write("pnpm-lock.yaml", currentLock);
    mutateLock("lock.fetch('packages').fetch('gsap@3.15.0').fetch('resolution')['integrity'] = 'sha512-web-only'");
    verify(true);
  });

  for (const [name, packageKey] of [
    ["root TypeScript integrity", "typescript@6.0.3"],
    ["native direct dependency integrity", "@tauri-apps/api@2.11.1"],
    ["shared build dependency integrity", "vite@8.1.3"],
    ["native transitive dependency integrity", "@jridgewell/sourcemap-codec@1.5.5"]
  ]) {
    test(`${name} invalidates native proof`, () => {
      mutateLock(`lock.fetch('packages').fetch(${JSON.stringify(packageKey)}).fetch('resolution')['integrity'] = 'sha512-changed'`);
      verify(false);
    });
  }

  for (const [name, mutation] of [
    ["native importer dependency", "lock.fetch('importers').fetch('apps/desktop').fetch('dependencies').delete('svelte')"],
    ["native transitive dependency", "lock.fetch('snapshots').fetch('svelte@5.56.4').fetch('dependencies').delete('acorn')"],
    ["global installation settings", "lock.fetch('settings')['autoInstallPeers'] = false"],
    ["unknown lockfile schema", "lock['lockfileVersion'] = '10.0'"],
    ["unknown reachable dependency metadata", "lock.fetch('packages').fetch('typescript@6.0.3')['futureDependencies'] = {}"],
    ["missing reachable package", "lock.fetch('packages').delete('typescript@6.0.3')"]
  ]) {
    test(`${name} invalidates native proof`, () => {
      mutateLock(mutation);
      verify(false);
    });
  }

  test("malformed lockfile invalidates native proof", () => {
    write("pnpm-lock.yaml", "lockfileVersion: [\n");
    commit();
    verify(false);
  });
  test("missing current lockfile invalidates native proof", () => {
    rmSync(join(fixture, "pnpm-lock.yaml"));
    commit();
    verify(false);
  });
  test("missing historical lockfile invalidates native proof", () => {
    rmSync(join(fixture, "pnpm-lock.yaml"));
    const missingLockCommit = commit();
    setEvidenceCommit(missingLockCommit);
    write("pnpm-lock.yaml", testedLock);
    commit();
    verify(false);
  });
  test("changed native source still invalidates native proof", () => {
    write("apps/desktop/src/proof-fixture.ts", "export const value = 2;\n");
    commit();
    verify(false, /package or proof-critical inputs changed/);
  });
  test("corrupt snapshot still fails before freshness checks", () => {
    const file = `${snapshot}/${targets[0]}/summary.tsv`;
    write(file, readFileSync(join(fixture, file), "utf8").replace("gui_launch\tpass", "gui_launch\tfail"));
    commit();
    verify(false, /gui_launch must be pass/);
  });
  test("missing tested commit still invalidates native proof", () => {
    setEvidenceCommit("f".repeat(40));
    commit();
    verify(false, /tested commit is not an ancestor/);
  });
  test("existing but unrelated tested commit still invalidates native proof", () => {
    git("checkout", "--quiet", "--orphan", "unrelated");
    commit();
    verify(false, /tested commit is not an ancestor/);
  });

  test("proof CLI returns 0 for equal application dependencies without Actions output", () => {
    write("pnpm-lock.yaml", currentLock);
    verifyLock(["application", testedCommit, commit()], 0);
  });
  test("proof CLI returns 1 for changed application dependencies without Actions output", () => {
    mutateLock("lock.fetch('packages').fetch('typescript@6.0.3').fetch('resolution')['integrity'] = 'sha512-changed'");
    verifyLock(["application", testedCommit, git("rev-parse", "HEAD")], 1);
  });
  test("proof CLI returns 2 for malformed lockfiles without Actions output", () => {
    write("pnpm-lock.yaml", "lockfileVersion: [\n");
    verifyLock(["application", testedCommit, commit()], 2);
  });
  test("proof CLI returns 2 for missing before revisions without Actions output", () => {
    verifyLock(["application", "f".repeat(40), baseline], 2);
  });
  test("proof CLI returns 2 for missing after revisions without Actions output", () => {
    verifyLock(["application", testedCommit, "f".repeat(40)], 2);
  });
  test("proof CLI returns 2 for wrong argument counts without Actions output", () => {
    verifyLock(["application", testedCommit], 2);
    verifyLock(["application", testedCommit, baseline, "extra"], 2);
  });
  test("proof CLI returns 2 for unsupported surfaces without Actions output", () => {
    verifyLock(["unsupported", testedCommit, baseline], 2);
  });

  console.log(`Native package proof snapshot regression tests passed (${passed} cases).`);
} finally {
  rmSync(fixture, { recursive: true, force: true });
}

function command(executable, args, cwd = fixture) {
  const result = spawnSync(executable, args, { cwd, encoding: "utf8" });
  assert.equal(result.status, 0, `${executable} ${args.join(" ")}: ${result.error ?? ""}${result.stderr}`);
  return result.stdout;
}

function git(...args) {
  return command("git", args).trim();
}

function write(file, content) {
  mkdirSync(join(fixture, dirname(file)), { recursive: true });
  writeFileSync(join(fixture, file), content);
}

function commit() {
  git("add", "--all");
  git("commit", "--quiet", "--allow-empty", "-m", "Native proof fixture");
  return git("rev-parse", "HEAD");
}

function setEvidenceCommit(value) {
  for (const target of targets) {
    const file = `${snapshot}/${target}/summary.tsv`;
    write(file, readFileSync(join(fixture, file), "utf8").replace(/^git_head\t[^\n]+/m, `git_head\t${value}`));
    write(`${snapshot}/${target}/git-head.txt`, `${value}\n`);
  }
}

function mutateLock(mutation) {
  const script = `lock = YAML.safe_load_file('pnpm-lock.yaml'); ${mutation}; File.write('pnpm-lock.yaml', YAML.dump(lock))`;
  command("ruby", ["-ryaml", "-e", script]);
  commit();
}

function verifyLock(args, expectedStatus) {
  const outputFile = join(fixture, ".git", "proof-mode-actions-output");
  const sentinel = "existing-output=must-remain-unchanged\n";
  for (const existsBefore of [false, true]) {
    rmSync(outputFile, { force: true });
    if (existsBefore) writeFileSync(outputFile, sentinel);
    const result = spawnSync("ruby", [lockHelper, "--verify-lockfile", ...args], {
      cwd: fixture,
      encoding: "utf8",
      env: { ...process.env, GITHUB_OUTPUT: outputFile }
    });
    const output = `${result.stdout}${result.stderr}`;
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, expectedStatus, output);
    assert.match(output, /ci-impact:/);
    assert.equal(existsSync(outputFile), existsBefore, "proof mode must not create GITHUB_OUTPUT");
    if (existsBefore) assert.equal(readFileSync(outputFile, "utf8"), sentinel, "proof mode must not modify GITHUB_OUTPUT");
  }
}

function verify(expectedPass, expectedFailure) {
  const result = spawnSync(process.execPath, [verifier], { cwd: fixture, encoding: "utf8" });
  const output = `${result.stdout}${result.stderr}`;
  assert.equal(result.error, undefined, String(result.error));
  assert.equal(result.status === 0, expectedPass, output);
  if (expectedPass) assert.match(output, /Native package proof snapshot verified: 4 targets/);
  else assert.match(output, expectedFailure ?? /verify-native-package-proof-snapshot:/);
}
