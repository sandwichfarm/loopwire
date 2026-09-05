#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const work = mkdtempSync(join(tmpdir(), "loopwire-cache-purge-"));
const deploy = resolve("scripts/deploy-docs-bunny.sh");
const dist = join(work, "site");
const trace = join(work, "requests.jsonl");
const apiKey = 'account-key-"$()&-must-not-leak';
mkdirSync(join(work, "bin"));
mkdirSync(join(dist, "docs/guide"), { recursive: true });
for (const file of ["index.html", "docs/index.html", "docs/guide/basic-usage.html"]) writeFileSync(join(dist, file), "site");
writeFileSync(join(dist, "install.sh"), "#!/bin/sh\necho installer\n");
writeFileSync(join(work, "bin/curl"), `#!/usr/bin/env node
const fs = require("node:fs");
const args = process.argv.slice(2);
const isPurge = args.some(arg => arg.endsWith("/purgeCache"));
const header = isPurge ? fs.readFileSync(0, "utf8") : "";
if (isPurge && process.env.PURGE_TEST_EXPECT_MANIFEST && !fs.existsSync(process.env.PURGE_TEST_EXPECT_MANIFEST)) process.exit(1);
fs.appendFileSync(process.env.PURGE_TEST_TRACE, JSON.stringify({args, header, isPurge}) + "\\n");
if (!isPurge && process.env.PURGE_TEST_UPLOAD_FAIL === "true") process.exit(22);
if (isPurge) {
  if (process.env.PURGE_TEST_NETWORK_FAIL === "true") {
    process.stderr.write(process.env.BUNNY_API_KEY);
    process.exit(7);
  }
  process.stdout.write(process.env.PURGE_TEST_STATUS || "204");
}
`, { mode: 0o755 });

function run(args = [], env = {}) {
  writeFileSync(trace, "");
  const environment = {
    ...process.env, PATH: `${join(work, "bin")}:${process.env.PATH}`, PURGE_TEST_TRACE: trace,
    BUNNY_STORAGE_ZONE: "test-zone", BUNNY_ACCESS_KEY: "storage-password", BUNNY_API_KEY: apiKey, BUNNY_PULL_ZONE_ID: "12345",
    ...env
  };
  const result = spawnSync("bash", [deploy, "--dist", dist, ...args], { env: environment, encoding: "utf8" });
  result.requests = readFileSync(trace, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
  assert.ok(!`${result.stdout}${result.stderr}`.includes(apiKey), "account key leaked into output");
  if (environment.BUNNY_API_KEY) {
    assert.ok(!`${result.stdout}${result.stderr}`.includes(environment.BUNNY_API_KEY), "entered account key leaked into output");
  }
  return result;
}

try {
  const manifest = join(work, "deployment-manifest.json");
  const success = run(["--purge-cache", "--deployment-manifest", manifest], { PURGE_TEST_EXPECT_MANIFEST: manifest });
  assert.equal(success.status, 0, success.stderr);
  assert.equal(success.requests.length, 5, "four uploads followed by one purge");
  assert.ok(success.requests.slice(0, -1).every(request => !request.isPurge));
  const purge = success.requests.at(-1);
  assert.ok(purge.isPurge);
  assert.ok(purge.args.includes("https://api.bunny.net/pullzone/12345/purgeCache"));
  assert.ok(purge.args.includes("POST"));
  assert.equal(purge.args[0], "--disable", "ignore curlrc so it cannot enable logging or redirects");
  assert.ok(!purge.args.some(arg => ["-L", "--location", "--location-trusted"].includes(arg)), "purge must not follow redirects");
  assert.ok(!purge.args.some(arg => ["-d", "--data", "--data-raw", "--data-binary", "--form"].includes(arg)), "purge needs no body");
  assert.equal(purge.args[purge.args.indexOf("--output") + 1], "/dev/null", "discard purge response bodies");
  assert.ok(purge.args.includes("@-"));
  assert.ok(!purge.args.some(arg => arg.includes(apiKey)), "account key must not appear in curl argv");
  assert.equal(purge.header, `AccessKey: ${apiKey}\n`);
  assert.ok(purge.args.includes("--max-time") && purge.args.includes("--retry"), "purge waits and retries must be bounded");
  assert.ok(purge.args.includes("--connect-timeout") && purge.args.includes("--retry-max-time"));
  assert.match(success.stdout, /purge accepted/i);
  assert.ok(!readFileSync(manifest, "utf8").includes(apiKey), "account key must not appear in deployment manifest");

  const legacy = run([], { BUNNY_API_KEY: "", BUNNY_PULL_ZONE_ID: "" });
  assert.equal(legacy.status, 0, legacy.stderr);
  assert.ok(legacy.requests.every(request => !request.isPurge), "upload-only CLI remains explicit");
  const dry = run(["--purge-cache", "--dry-run"], { BUNNY_API_KEY: "", BUNNY_ACCESS_KEY: "" });
  assert.equal(dry.status, 0, dry.stderr);
  assert.equal(dry.requests.length, 0);
  assert.match(dry.stdout, /would purge/i);

  for (const values of [{ BUNNY_API_KEY: "" }, { BUNNY_API_KEY: "bad\rkey" }, { BUNNY_API_KEY: "bad\tkey" },
    { BUNNY_API_KEY: "bad\nkey" }, { BUNNY_API_KEY: "bad\x01key" }, { BUNNY_API_KEY: "bad\x7fkey" },
    { BUNNY_PULL_ZONE_ID: "" }, { BUNNY_PULL_ZONE_ID: "0" }, { BUNNY_PULL_ZONE_ID: "000" },
    { BUNNY_PULL_ZONE_ID: "-1" }, { BUNNY_PULL_ZONE_ID: "1e3" }, { BUNNY_PULL_ZONE_ID: "1/other" },
    { BUNNY_PULL_ZONE_ID: "9223372036854775808" }]) {
    const result = run(["--purge-cache"], values);
    assert.notEqual(result.status, 0, "invalid configuration must fail");
    assert.equal(result.requests.length, 0, "invalid purge configuration must fail before uploads");
  }
  for (const id of ["1", "00012345", "9223372036854775807"]) {
    const result = run(["--purge-cache"], { BUNNY_PULL_ZONE_ID: id, BUNNY_REMOTE_PREFIX: "preview/site" });
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.requests.at(-1).args.includes(`https://api.bunny.net/pullzone/${id}/purgeCache`));
  }
  const invalidDry = run(["--purge-cache", "--dry-run"], { BUNNY_PULL_ZONE_ID: "invalid" });
  assert.notEqual(invalidDry.status, 0, "dry run still requires a valid zone ID");
  assert.equal(invalidDry.requests.length, 0);
  const failedUpload = run(["--purge-cache"], { PURGE_TEST_UPLOAD_FAIL: "true" });
  assert.notEqual(failedUpload.status, 0);
  assert.ok(failedUpload.requests.every(request => !request.isPurge));
  const failedManifest = run(["--purge-cache", "--deployment-manifest", "/dev/null/manifest.json"]);
  assert.notEqual(failedManifest.status, 0);
  assert.ok(failedManifest.requests.every(request => !request.isPurge));
  for (const status of ["200", "299"]) {
    assert.equal(run(["--purge-cache"], { PURGE_TEST_STATUS: status }).status, 0);
  }
  for (const status of ["199", "301", "401", "403", "429", "500", apiKey]) {
    const result = run(["--purge-cache"], { PURGE_TEST_STATUS: status });
    assert.notEqual(result.status, 0, `HTTP ${status} must not report successful deployment`);
    assert.doesNotMatch(result.stdout, /purge accepted/i);
  }
  assert.notEqual(run(["--purge-cache"], { PURGE_TEST_NETWORK_FAIL: "true" }).status, 0);
  console.log("Bunny cache purge regressions passed: ordering, dry run, preflight, failed uploads/manifests, HTTP/network errors and secrecy.");
} finally {
  rmSync(work, { recursive: true, force: true });
}
