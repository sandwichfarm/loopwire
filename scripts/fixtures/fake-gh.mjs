#!/usr/bin/env node
import { appendFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const stateDir = process.env.LOOPWIRE_FAKE_GH_STATE_DIR;
if (!stateDir) fail("LOOPWIRE_FAKE_GH_STATE_DIR is required");
mkdirSync(stateDir, { recursive: true });

const args = process.argv.slice(2);
const stdin = readFileSync(0);
appendFileSync(join(stateDir, "calls.jsonl"), `${JSON.stringify({ args, stdinBase64: stdin.toString("base64") })}\n`);

const statePath = join(stateDir, "state.json");
const state = existsSync(statePath)
  ? JSON.parse(readFileSync(statePath, "utf8"))
  : { variables: {}, secrets: {} };

if (args[0] === "auth" && args[1] === "status") process.exit(0);

if (args[0] === "repo" && args[1] === "view") {
  const explicit = args[2] && !args[2].startsWith("-") ? args[2] : "sandwichfarm/loopwire";
  process.stdout.write(`${JSON.stringify({ nameWithOwner: explicit })}\n`);
  process.exit(0);
}

if (args[0] === "variable" && args[1] === "list") {
  process.stdout.write(`${JSON.stringify(Object.keys(state.variables).map((name) => ({ name })))}\n`);
  process.exit(0);
}

if (args[0] === "variable" && args[1] === "set") {
  const name = args[2];
  maybeFail("variable", name);
  state.variables[name] = stdin.toString("base64");
  saveState();
  process.exit(0);
}

if (args[0] === "variable" && args[1] === "get") {
  const name = args[2];
  if (!(name in state.variables)) process.exit(1);
  const storedValue = Buffer.from(state.variables[name], "base64").toString("utf8");
  const value = process.env.LOOPWIRE_FAKE_GH_CORRUPT_VARIABLE === name ? `${storedValue}-corrupted` : storedValue;
  process.stdout.write(
    `${JSON.stringify({ name, value })}\n`
  );
  process.exit(0);
}

if (args[0] === "secret" && args[1] === "list") {
  process.stdout.write(`${JSON.stringify(Object.keys(state.secrets).map((name) => ({ name })))}\n`);
  process.exit(0);
}

if (args[0] === "secret" && args[1] === "set") {
  const name = args[2];
  maybeFail("secret", name);
  state.secrets[name] = stdin.toString("base64");
  saveState();
  process.exit(0);
}

fail(`unsupported fake gh command: ${args.join(" ")}`);

function maybeFail(type, name) {
  if (process.env.LOOPWIRE_FAKE_GH_FAIL_ON === `${type}:${name}`) process.exit(23);
}

function saveState() {
  const temporaryPath = `${statePath}.tmp`;
  writeFileSync(temporaryPath, `${JSON.stringify(state, null, 2)}\n`);
  renameSync(temporaryPath, statePath);
}

function fail(message) {
  process.stderr.write(`fake-gh: ${message}\n`);
  process.exit(2);
}
