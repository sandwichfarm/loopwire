import { mkdtemp, readFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { describe, expect, it } from "vitest";
import { runDspProviderCli } from "../src/dsp-provider-cli.js";

describe("runDspProviderCli", () => {
  it("seeds and reads source buffers from the provider store", async () => {
    const storeDir = await temporaryStore();
    const seed = await runProvider([
      "seed-source",
      "--source-id",
      "mic",
      "--channels",
      "2",
      "--frames",
      "3",
      "--value",
      "1",
      "--store-dir",
      storeDir
    ]);
    const read = await runProvider([
      "read-source",
      "--source-id",
      "mic",
      "--channels",
      "2",
      "--frames",
      "2",
      "--store-dir",
      storeDir
    ]);

    expect(seed).toMatchObject({ exitCode: 0, stderr: "" });
    expect(JSON.parse(seed.stdout)).toEqual({ ok: true, sourceId: "mic", frames: 3 });
    expect(read).toMatchObject({ exitCode: 0, stderr: "" });
    expect(JSON.parse(read.stdout)).toEqual({
      channels: [
        [1, 0.5],
        [0.5, 1 / 3]
      ]
    });
  });

  it("reports missing sources without failing the provider command", async () => {
    const storeDir = await temporaryStore();
    const result = await runProvider([
      "read-source",
      "--source-id",
      "browser",
      "--channels",
      "2",
      "--frames",
      "2",
      "--store-dir",
      storeDir
    ]);

    expect(result).toMatchObject({ exitCode: 0, stderr: "" });
    expect(JSON.parse(result.stdout)).toEqual({ missing: true });
  });

  it("writes, verifies, and clears rendered outputs", async () => {
    const storeDir = await temporaryStore();
    const rendered = {
      outputId: "program",
      peak: 0.75,
      channels: [
        [0.75, 0.25],
        [0.5, -0.25]
      ]
    };
    const write = await runProvider([
      "write-output",
      "--output-id",
      "program",
      "--channels",
      "2",
      "--frames",
      "2",
      "--peak",
      "0.75",
      "--configuration-id",
      "studio",
      "--store-dir",
      storeDir
    ], JSON.stringify(rendered));
    const verify = await runProvider([
      "verify-output",
      "--output-id",
      "program",
      "--channels",
      "2",
      "--frames",
      "2",
      "--peak",
      "0.75",
      "--configuration-id",
      "studio",
      "--store-dir",
      storeDir
    ], JSON.stringify(rendered));
    const storedOutput = await readFile(join(storeDir, "outputs", "studio", "program.json"), "utf8");
    const clear = await runProvider([
      "clear-output",
      "--configuration-id",
      "studio",
      "--output-id",
      "program",
      "--store-dir",
      storeDir
    ]);
    const verifyAfterClear = await runProvider([
      "verify-output",
      "--output-id",
      "program",
      "--channels",
      "2",
      "--frames",
      "2",
      "--peak",
      "0.75",
      "--configuration-id",
      "studio",
      "--store-dir",
      storeDir
    ], JSON.stringify(rendered));

    expect(write).toMatchObject({ exitCode: 0, stderr: "" });
    expect(JSON.parse(write.stdout)).toEqual({ ok: true, configurationId: "studio", outputId: "program" });
    expect(storedOutput).toContain('"peak":0.75');
    expect(verify).toMatchObject({ exitCode: 0, stderr: "" });
    expect(JSON.parse(verify.stdout)).toEqual({ ok: true, message: "DSP output program verified" });
    expect(clear).toMatchObject({ exitCode: 0, stderr: "" });
    expect(JSON.parse(clear.stdout)).toEqual({ ok: true, configurationId: "studio", outputId: "program", cleared: true });
    expect(JSON.parse(verifyAfterClear.stdout)).toEqual({
      ok: false,
      message: "DSP output program has not been written"
    });
  });

  it("does not verify stale output from another configuration with the same output id", async () => {
    const storeDir = await temporaryStore();
    const rendered = {
      outputId: "program",
      peak: 0.75,
      channels: [
        [0.75, 0.25],
        [0.5, -0.25]
      ]
    };
    await runProvider([
      "write-output",
      "--output-id",
      "program",
      "--channels",
      "2",
      "--frames",
      "2",
      "--peak",
      "0.75",
      "--configuration-id",
      "studio-a",
      "--store-dir",
      storeDir
    ], JSON.stringify(rendered));
    const verifyOtherConfiguration = await runProvider([
      "verify-output",
      "--output-id",
      "program",
      "--channels",
      "2",
      "--frames",
      "2",
      "--peak",
      "0.75",
      "--configuration-id",
      "studio-b",
      "--store-dir",
      storeDir
    ], JSON.stringify(rendered));

    expect(JSON.parse(verifyOtherConfiguration.stdout)).toEqual({
      ok: false,
      message: "DSP output program has not been written"
    });
  });

  it("rejects output payloads that do not match command metadata", async () => {
    const storeDir = await temporaryStore();
    const result = await runProvider([
      "write-output",
      "--output-id",
      "program",
      "--channels",
      "2",
      "--frames",
      "2",
      "--peak",
      "0.5",
      "--configuration-id",
      "studio",
      "--store-dir",
      storeDir
    ], JSON.stringify({ channels: [[0.25], [0.25]] }));

    expect(result.exitCode).toBe(2);
    expect(result.stderr).toContain("fewer than 2 frame(s)");
  });
});

async function temporaryStore(): Promise<string> {
  return mkdtemp(join(tmpdir(), "loopwire-dsp-provider-"));
}

async function runProvider(
  argv: readonly string[],
  stdin = ""
): Promise<{ readonly exitCode: number; readonly stdout: string; readonly stderr: string }> {
  let stdout = "";
  let stderr = "";
  const exitCode = await runDspProviderCli(argv, {
    stdin,
    stdout: (text) => {
      stdout += text;
    },
    stderr: (text) => {
      stderr += text;
    }
  });

  return { exitCode, stdout, stderr };
}
