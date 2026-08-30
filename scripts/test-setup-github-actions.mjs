#!/usr/bin/env node
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const helperPath = join(scriptDir, "setup-github-actions.mjs");
const fakeGhPath = join(scriptDir, "fixtures", "fake-gh.mjs");
const temporaryRoot = mkdtempSync(join(tmpdir(), "loopwire-github-setup-test-"));

try {
  testHelpAndRequiredNames();
  testDeployPromptPreservesExactValues();
  testWindowsLineEndingsKeepPromptBoundaries();
  testDryRunNeverInvokesGhOrLeaksSecrets();
  testFinalKeyBytesWithoutTrailingNewline();
  testInvalidInputStopsBeforeRemotePreflight();
  testOversizeSecretIsRejectedWithoutTruncation();
  testMismatchedAndSymlinkKeysStopBeforeWrites();
  testVariableReadbackCorruptionStopsBeforeSecrets();
  testRepeatedSetupReplacesInsteadOfAppending();
  testPartialFailureNamesCompletedWritesWithoutValues();
  process.stdout.write("GitHub Actions setup transport tests passed (11 cases).\n");
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true });
}

function testHelpAndRequiredNames() {
  const help = run(["--help"], "");
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Windows, macOS, and Linux|Configure Loopwire GitHub Actions/);
  assert.match(help.stdout, /Values are never accepted as CLI flags or environment variables/);

  const required = run(["--", "--print-required", "--scope", "final"], "");
  assert.equal(required.status, 0, required.stderr);
  assert.match(required.stdout, /variable: BUNNY_STORAGE_ZONE/);
  assert.match(required.stdout, /secret: BUNNY_ACCESS_KEY/);
  assert.match(required.stdout, /secret: LOOPWIRE_RELEASE_PRIVATE_KEY/);
}

function testDeployPromptPreservesExactValues() {
  const stateDir = newStateDir("deploy-exact");
  const values = {
    zone: "loopwire-zone",
    endpoint: "https://ny.storage.bunnycdn.com",
    hostname: "docs.example.test",
    prefix: "preview-v1",
    access: "  '\"$();|& Ω\t  "
  };
  const input = [values.zone, values.endpoint, values.hostname, values.prefix, values.access, "APPLY"].join("\n");
  const result = run(["--repo", "sandwichfarm/loopwire", "--scope", "deploy"], input, { stateDir });
  assert.equal(result.status, 0, result.stderr);

  const state = readState(stateDir);
  assertBytes(state.variables.BUNNY_STORAGE_ZONE, values.zone);
  assertBytes(state.variables.BUNNY_STORAGE_ENDPOINT, values.endpoint);
  assertBytes(state.variables.BUNNY_PULL_ZONE_HOSTNAME, values.hostname);
  assertBytes(state.variables.BUNNY_REMOTE_PREFIX, values.prefix);
  assertBytes(state.secrets.BUNNY_ACCESS_KEY, values.access);
  assertNoSecretLeak(result, [values.access]);
  assert.match(result.stderr, /FTP & API Access/);
  assert.match(result.stderr, /Pull Zones/);

  const calls = readCalls(stateDir);
  for (const call of calls.filter((entry) => entry.args[1] === "set")) {
    assert.ok(!call.args.includes(values.access), "secret must not appear in gh argv");
  }

  const check = run(["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--check"], "", {
    stateDir
  });
  assert.equal(check.status, 0, check.stderr);
  assert.match(check.stdout, /ok: GitHub Actions deploy configuration is present/);
}

function testWindowsLineEndingsKeepPromptBoundaries() {
  const stateDir = newStateDir("crlf-boundaries");
  const access = "secret-after-four-distinct-prompts";
  const lines = ["zone-crlf", "", "docs-crlf.example.test", "folder/subfolder", access];
  const result = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--yes"],
    `${lines.join("\r\n")}\r\n`,
    { stateDir }
  );
  assert.equal(result.status, 0, result.stderr);
  const state = readState(stateDir);
  assertBytes(state.variables.BUNNY_STORAGE_ZONE, "zone-crlf");
  assertBytes(state.variables.BUNNY_STORAGE_ENDPOINT, "https://storage.bunnycdn.com");
  assertBytes(state.variables.BUNNY_PULL_ZONE_HOSTNAME, "docs-crlf.example.test");
  assertBytes(state.variables.BUNNY_REMOTE_PREFIX, "folder/subfolder");
  assertBytes(state.secrets.BUNNY_ACCESS_KEY, access);
}

function testDryRunNeverInvokesGhOrLeaksSecrets() {
  const stateDir = newStateDir("dry-run");
  const access = "dry-run-secret-$() with spaces";
  const input = ["dry-run-zone", "", "", "", access].join("\n");
  const result = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--dry-run"],
    input,
    { stateDir }
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(join(stateDir, "calls.jsonl")), false, "dry-run must not invoke gh");
  assert.match(result.stdout, /variable: BUNNY_STORAGE_ZONE/);
  assert.match(result.stdout, /secret: BUNNY_ACCESS_KEY/);
  assertNoSecretLeak(result, [access]);
}

function testFinalKeyBytesWithoutTrailingNewline() {
  const stateDir = newStateDir("final-key");
  const workDir = join(temporaryRoot, "cwd with spaces");
  const keyDir = join(workDir, "key files");
  mkdirSync(keyDir, { recursive: true });
  const { privateKey, publicKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" }
  });
  const privateWithoutNewline = Buffer.from(privateKey.replace(/\n$/, ""), "utf8");
  const publicWithoutNewline = Buffer.from(publicKey.replace(/\n$/, ""), "utf8");
  const privatePath = join(keyDir, "release private.pem");
  const publicPath = join(keyDir, "release public.pem");
  writeFileSync(privatePath, privateWithoutNewline);
  writeFileSync(publicPath, publicWithoutNewline);

  const access = "final-secret-Ω-'\"-$()";
  const input = [
    "final-zone",
    "",
    "docs.final.example.test",
    "",
    access,
    relative(workDir, privatePath),
    "",
    "APPLY"
  ].join("\n");
  const result = run(
    [
      "--repo",
      "sandwichfarm/loopwire",
      "--scope",
      "final",
      "--public-key-file",
      publicPath
    ],
    input,
    { stateDir, cwd: workDir }
  );
  assert.equal(result.status, 0, result.stderr);
  const state = readState(stateDir);
  assert.deepEqual(Buffer.from(state.secrets.LOOPWIRE_RELEASE_PRIVATE_KEY, "base64"), privateWithoutNewline);
  assertBytes(state.secrets.BUNNY_ACCESS_KEY, access);
  assertNoSecretLeak(result, [access, privateWithoutNewline.toString("utf8")]);
  assert.match(result.stderr, /pnpm release:prepare-key/);
}

function testInvalidInputStopsBeforeRemotePreflight() {
  const stateDir = newStateDir("invalid-before-write");
  const input = ["zone-with-space "].join("\n");
  const result = run(["--repo", "sandwichfarm/loopwire", "--scope", "deploy"], input, { stateDir });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /leading or trailing whitespace; refusing to modify it silently/);
  assert.equal(existsSync(join(stateDir, "calls.jsonl")), false, "invalid input must stop before gh preflight");
}

function testOversizeSecretIsRejectedWithoutTruncation() {
  const stateDir = newStateDir("oversize");
  const hugeSecret = "x".repeat(48 * 1024 + 1);
  const input = ["oversize-zone", "", "", "", hugeSecret].join("\n");
  const result = run(["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--yes"], input, {
    stateDir,
    maxBuffer: 2 * 1024 * 1024
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /exceeds GitHub's 48 KB value limit; input was not truncated/);
  assertNoSecretLeak(result, [hugeSecret]);
  assert.equal(existsSync(join(stateDir, "calls.jsonl")), false);
}

function testMismatchedAndSymlinkKeysStopBeforeWrites() {
  const stateDir = newStateDir("bad-keys");
  const keyDir = join(temporaryRoot, "bad keys");
  mkdirSync(keyDir, { recursive: true });
  const first = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" }
  });
  const second = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" }
  });
  const privatePath = join(keyDir, "private.pem");
  const wrongPublicPath = join(keyDir, "wrong-public.pem");
  writeFileSync(privatePath, first.privateKey);
  writeFileSync(wrongPublicPath, second.publicKey);
  const input = `${[
    "bad-key-zone",
    "",
    "docs.bad-key.example.test",
    "",
    "bad-key-access",
    privatePath,
    ""
  ].join("\n")}\n`;
  const mismatch = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "final", "--public-key-file", wrongPublicPath],
    input,
    { stateDir }
  );
  assert.notEqual(mismatch.status, 0);
  assert.match(mismatch.stderr, /does not match the supplied public key/);
  assert.equal(existsSync(join(stateDir, "calls.jsonl")), false);

  const symlinkState = newStateDir("symlink-key");
  const symlinkPath = join(keyDir, "private-link.pem");
  try {
    symlinkSync(privatePath, symlinkPath);
  } catch {
    return;
  }
  const symlinkInput = `${[
    "symlink-zone",
    "",
    "docs.symlink.example.test",
    "",
    "symlink-access",
    symlinkPath,
    ""
  ].join("\n")}\n`;
  const symlink = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "final", "--public-key-file", wrongPublicPath],
    symlinkInput,
    { stateDir: symlinkState }
  );
  assert.notEqual(symlink.status, 0);
  assert.match(symlink.stderr, /must not be a symbolic link/);
  assert.equal(existsSync(join(symlinkState, "calls.jsonl")), false);
}

function testPartialFailureNamesCompletedWritesWithoutValues() {
  const stateDir = newStateDir("partial-failure");
  const access = "must-not-leak-partial-$()";
  const input = ["partial-zone", "", "", "partial-prefix", access].join("\n");
  const result = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--yes"],
    input,
    { stateDir, failOn: "secret:BUNNY_ACCESS_KEY" }
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /write failed for secret:BUNNY_ACCESS_KEY/);
  assert.match(result.stderr, /variable:BUNNY_STORAGE_ZONE/);
  assert.match(result.stderr, /remaining names were not attempted/);
  assertNoSecretLeak(result, [access]);
  const state = readState(stateDir);
  assert.ok(state.variables.BUNNY_STORAGE_ZONE);
  assert.equal(state.secrets.BUNNY_ACCESS_KEY, undefined);
}

function testVariableReadbackCorruptionStopsBeforeSecrets() {
  const stateDir = newStateDir("corrupt-readback");
  const access = "must-not-write-after-corrupt-readback";
  const input = ["readback-zone", "", "", "", access].join("\n");
  const result = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--yes"],
    input,
    { stateDir, corruptVariable: "BUNNY_STORAGE_ZONE" }
  );
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /GitHub variable readback did not match the entered UTF-8 value/);
  assertNoSecretLeak(result, [access]);
  const state = readState(stateDir);
  assert.ok(state.variables.BUNNY_STORAGE_ZONE);
  assert.equal(state.secrets.BUNNY_ACCESS_KEY, undefined);
}

function testRepeatedSetupReplacesInsteadOfAppending() {
  const stateDir = newStateDir("replace-not-append");
  const first = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--yes"],
    ["first-zone", "", "", "", "first-secret"].join("\n"),
    { stateDir }
  );
  assert.equal(first.status, 0, first.stderr);
  const second = run(
    ["--repo", "sandwichfarm/loopwire", "--scope", "deploy", "--yes"],
    ["second-zone", "", "", "", "second-secret"].join("\n"),
    { stateDir }
  );
  assert.equal(second.status, 0, second.stderr);
  const state = readState(stateDir);
  assertBytes(state.variables.BUNNY_STORAGE_ZONE, "second-zone");
  assertBytes(state.secrets.BUNNY_ACCESS_KEY, "second-secret");
}

function run(args, input, options = {}) {
  const stateDir = options.stateDir || newStateDir("default");
  return spawnSync(process.execPath, [helperPath, ...args], {
    cwd: options.cwd || resolve(scriptDir, ".."),
    input,
    encoding: "utf8",
    maxBuffer: options.maxBuffer || 1024 * 1024,
    windowsHide: true,
    env: {
      ...process.env,
      LOOPWIRE_SETUP_TEST_MODE: "1",
      LOOPWIRE_GH_BIN: process.execPath,
      LOOPWIRE_GH_SCRIPT: fakeGhPath,
      LOOPWIRE_FAKE_GH_STATE_DIR: stateDir,
      ...(options.failOn ? { LOOPWIRE_FAKE_GH_FAIL_ON: options.failOn } : {}),
      ...(options.corruptVariable
        ? { LOOPWIRE_FAKE_GH_CORRUPT_VARIABLE: options.corruptVariable }
        : {})
    }
  });
}

function newStateDir(name) {
  const directory = join(temporaryRoot, name);
  mkdirSync(directory, { recursive: true });
  return directory;
}

function readState(stateDir) {
  const path = join(stateDir, "state.json");
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : { variables: {}, secrets: {} };
}

function readCalls(stateDir) {
  const path = join(stateDir, "calls.jsonl");
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function assertBytes(base64, expected) {
  assert.deepEqual(Buffer.from(base64, "base64"), Buffer.from(expected, "utf8"));
}

function assertNoSecretLeak(result, secrets) {
  const output = `${result.stdout}\n${result.stderr}`;
  for (const secret of secrets) assert.ok(!output.includes(secret), "secret material leaked to process output");
}
