import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { describe, expect, it } from "vitest";
import { runJackPortsCli } from "../src/jack-ports-cli.js";

const ensureArgs = [
  "ensure",
  "--configuration-id",
  "JACK Mix",
  "--requirement",
  "route-source:loopwire-owned:mic:loopwire_jack_mix_input_mic:2",
  "--requirement",
  "route-target:loopwire-owned:program:loopwire_jack_mix_program:2",
  "--port",
  "loopwire_jack_mix_input_mic:capture_2",
  "--port",
  "loopwire_jack_mix_input_mic:capture_1",
  "--port",
  "loopwire_jack_mix_program:playback_1"
] as const;

describe("runJackPortsCli", () => {
  it("records the requested JACK provision plan and fails closed without a delegate", async () => {
    const manifest = join(await temporaryDir(), "provision.json");
    const result = await runCli([...ensureArgs, "--manifest-file", manifest]);
    const payload = JSON.parse(await readFile(manifest, "utf8"));

    expect(result.exitCode).toBe(2);
    expect(result.stdout).toBe("");
    expect(result.stderr).toContain("did not create live JACK clients");
    expect(payload).toMatchObject({
      kind: "loopwire.jack-ports.provision-plan",
      version: 1,
      configurationId: "JACK Mix",
      delegateCommand: null
    });
    expect(payload.missingPorts).toEqual([
      "loopwire_jack_mix_input_mic:capture_1",
      "loopwire_jack_mix_input_mic:capture_2",
      "loopwire_jack_mix_program:playback_1"
    ]);
    expect(payload.requirements.map((item: { readonly deviceName: string }) => item.deviceName)).toEqual([
      "loopwire_jack_mix_input_mic",
      "loopwire_jack_mix_program"
    ]);
  });

  it("accepts the pnpm argument separator before ensure arguments", async () => {
    const manifest = join(await temporaryDir(), "provision.json");
    const result = await runCli(["--", ...ensureArgs, "--manifest-file", manifest]);
    const payload = JSON.parse(await readFile(manifest, "utf8"));

    expect(result.exitCode).toBe(2);
    expect(payload.configurationId).toBe("JACK Mix");
  });

  it("delegates live JACK client creation with the exact ensure arguments", async () => {
    const dir = await temporaryDir();
    const delegate = join(dir, "delegate.mjs");
    const log = join(dir, "delegate.log");
    const manifest = join(dir, "manifest.json");

    await writeFile(
      delegate,
      [
        "#!/usr/bin/env node",
        "import { appendFileSync } from 'node:fs';",
        "appendFileSync(process.env.DELEGATE_LOG, `${process.argv.slice(2).join(' ')}\\n`);",
        "process.stdout.write('created live JACK ports\\n');"
      ].join("\n"),
      { mode: 0o755 }
    );

    const result = await runCli([...ensureArgs, "--manifest-file", manifest], {
      DELEGATE_LOG: log,
      LOOPWIRE_JACK_PORTS_DELEGATE: delegate
    });

    expect(result).toEqual({
      exitCode: 0,
      stdout: "created live JACK ports\n",
      stderr: ""
    });
    await expect(readFile(log, "utf8")).resolves.toBe(`${ensureArgs.join(" ")} --manifest-file ${manifest}\n`);
    await expect(readFile(manifest, "utf8")).resolves.toContain(`"delegateCommand": "${delegate}"`);
  });

  it("does not forward the wrapper-only delegate flag to the live provider", async () => {
    const dir = await temporaryDir();
    const delegate = join(dir, "delegate.mjs");
    const log = join(dir, "delegate.log");
    const manifest = join(dir, "manifest.json");

    await writeFile(
      delegate,
      [
        "#!/usr/bin/env node",
        "import { appendFileSync } from 'node:fs';",
        "appendFileSync(process.env.DELEGATE_LOG, `${process.argv.slice(2).join(' ')}\\n`);"
      ].join("\n"),
      { mode: 0o755 }
    );

    const result = await runCli(
      [
        ...ensureArgs,
        "--manifest-file",
        manifest,
        "--delegate-command",
        delegate
      ],
      { DELEGATE_LOG: log }
    );

    expect(result.exitCode).toBe(0);
    await expect(readFile(log, "utf8")).resolves.toBe(`${ensureArgs.join(" ")} --manifest-file ${manifest}\n`);
  });

  it("rejects malformed requirements before writing a manifest", async () => {
    const manifest = join(await temporaryDir(), "bad.json");
    const result = await runCli([
      "ensure",
      "--configuration-id",
      "JACK Mix",
      "--requirement",
      "route-source:too-short",
      "--port",
      "loopwire_jack_mix_input_mic:capture_1",
      "--manifest-file",
      manifest
    ]);

    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("Invalid --requirement value");
    await expect(readFile(manifest, "utf8")).rejects.toMatchObject({ code: "ENOENT" });
  });
});

async function temporaryDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "loopwire-jack-ports-"));
}

async function runCli(
  argv: readonly string[],
  env: NodeJS.ProcessEnv = {}
): Promise<{ readonly exitCode: number; readonly stdout: string; readonly stderr: string }> {
  let stdout = "";
  let stderr = "";
  const exitCode = await runJackPortsCli(argv, {
    env,
    stdout: (text) => {
      stdout += text;
    },
    stderr: (text) => {
      stderr += text;
    }
  });

  return { exitCode, stdout, stderr };
}
