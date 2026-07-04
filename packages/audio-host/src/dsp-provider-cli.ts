#!/usr/bin/env node
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

type DspProviderCommand =
  | "capabilities"
  | "read-source"
  | "write-output"
  | "verify-output"
  | "clear-output"
  | "seed-source";

interface DspProviderCliIo {
  readonly env?: NodeJS.ProcessEnv;
  readonly stdin?: string;
  stdout(text: string): void;
  stderr(text: string): void;
}

interface ParsedArgs {
  readonly command: DspProviderCommand | undefined;
  readonly storeDir: string;
  readonly sourceId: string | undefined;
  readonly outputId: string | undefined;
  readonly configurationId: string | undefined;
  readonly channels: number | undefined;
  readonly frames: number | undefined;
  readonly peak: number | undefined;
  readonly value: number | undefined;
}

interface BufferPayload {
  readonly channels: readonly (readonly number[])[];
}

const defaultSeedValue = 1;
const peakTolerance = 0.000001;

export async function runDspProviderCli(argv: readonly string[], io: DspProviderCliIo): Promise<number> {
  try {
    const parsed = parseArgs(argv, io.env ?? process.env);

    if (!parsed.command) {
      io.stdout(usage());
      return 0;
    }

    switch (parsed.command) {
      case "capabilities":
        return capabilities(io);
      case "read-source":
        return await readSource(parsed, io);
      case "write-output":
        return await writeOutput(parsed, io);
      case "verify-output":
        return await verifyOutput(parsed, io);
      case "clear-output":
        return await clearOutput(parsed, io);
      case "seed-source":
        return await seedSource(parsed, io);
    }
  } catch (error) {
    io.stderr(`${errorMessage(error)}\n`);
    return 2;
  }
}

function capabilities(io: DspProviderCliIo): number {
  const payload = {
    ok: true,
    providerKind: "file-backed",
    supportsLiveGraph: false,
    operations: ["read-source", "write-output", "verify-output", "clear-output", "seed-source"]
  };

  io.stdout(`${JSON.stringify(payload)}\n`);
  return 0;
}

function parseArgs(argv: readonly string[], env: NodeJS.ProcessEnv): ParsedArgs {
  const command = argv[0];

  if (command === "-h" || command === "--help" || command === undefined) {
    return {
      command: undefined,
      storeDir: defaultStoreDir(env),
      sourceId: undefined,
      outputId: undefined,
      configurationId: undefined,
      channels: undefined,
      frames: undefined,
      peak: undefined,
      value: undefined
    };
  }

  if (!isCommand(command)) {
    throw new Error(`Unknown DSP provider command: ${command}`);
  }

  const values = new Map<string, string>();

  for (let index = 1; index < argv.length; index += 1) {
    const flag = argv[index];

    if (!flag?.startsWith("--")) {
      throw new Error(`Unknown DSP provider argument: ${flag ?? ""}`);
    }

    const value = argv[index + 1];

    if (!value || value.startsWith("--")) {
      throw new Error(`${flag} requires a value`);
    }

    values.set(flag, value);
    index += 1;
  }

  return {
    command,
    storeDir: values.get("--store-dir") ?? defaultStoreDir(env),
    sourceId: values.get("--source-id"),
    outputId: values.get("--output-id"),
    configurationId: values.get("--configuration-id"),
    channels: optionalPositiveInteger(values.get("--channels"), "--channels"),
    frames: optionalPositiveInteger(values.get("--frames"), "--frames"),
    peak: optionalFiniteNumber(values.get("--peak"), "--peak"),
    value: optionalFiniteNumber(values.get("--value"), "--value")
  };
}

async function readSource(parsed: ParsedArgs, io: DspProviderCliIo): Promise<number> {
  const sourceId = requireValue(parsed.sourceId, "--source-id");
  const channels = requireValue(parsed.channels, "--channels");
  const path = sourcePath(parsed.storeDir, sourceId);

  let payload: BufferPayload;

  try {
    payload = JSON.parse(await readFile(path, "utf8")) as BufferPayload;
  } catch (error) {
    if (isMissingFile(error)) {
      io.stdout(`${JSON.stringify({ missing: true })}\n`);
      return 0;
    }

    throw error;
  }

  const normalized = normalizeBufferPayload(payload, sourceId, channels, parsed.frames);
  io.stdout(`${JSON.stringify({ channels: normalized.channels })}\n`);
  return 0;
}

async function writeOutput(parsed: ParsedArgs, io: DspProviderCliIo): Promise<number> {
  const configurationId = requireValue(parsed.configurationId, "--configuration-id");
  const outputId = requireValue(parsed.outputId, "--output-id");
  const channels = requireValue(parsed.channels, "--channels");
  const frames = requireValue(parsed.frames, "--frames");
  const peak = requireValue(parsed.peak, "--peak");
  const payload = parsePayload(io.stdin ?? "", "write-output", outputId);
  const normalized = normalizeRenderedPayload(payload, outputId, channels, frames, peak);
  const path = outputPath(parsed.storeDir, configurationId, outputId);

  await writeJson(path, { configurationId, outputId, peak, channels: normalized.channels });
  io.stdout(`${JSON.stringify({ ok: true, configurationId, outputId })}\n`);
  return 0;
}

async function verifyOutput(parsed: ParsedArgs, io: DspProviderCliIo): Promise<number> {
  const configurationId = requireValue(parsed.configurationId, "--configuration-id");
  const outputId = requireValue(parsed.outputId, "--output-id");
  const channels = requireValue(parsed.channels, "--channels");
  const frames = requireValue(parsed.frames, "--frames");
  const peak = requireValue(parsed.peak, "--peak");
  const expected = normalizeRenderedPayload(
    parsePayload(io.stdin ?? "", "verify-output", outputId),
    outputId,
    channels,
    frames,
    peak
  );

  try {
    const actual = normalizeRenderedPayload(
      JSON.parse(await readFile(outputPath(parsed.storeDir, configurationId, outputId), "utf8")) as BufferPayload,
      outputId,
      channels,
      frames,
      peak
    );

    if (!buffersEqual(actual.channels, expected.channels)) {
      io.stdout(`${JSON.stringify({ ok: false, message: `DSP output ${outputId} does not match stored output` })}\n`);
      return 0;
    }

    io.stdout(`${JSON.stringify({ ok: true, message: `DSP output ${outputId} verified` })}\n`);
    return 0;
  } catch (error) {
    if (!isMissingFile(error)) {
      throw error;
    }

    io.stdout(`${JSON.stringify({ ok: false, message: `DSP output ${outputId} has not been written` })}\n`);
    return 0;
  }
}

async function clearOutput(parsed: ParsedArgs, io: DspProviderCliIo): Promise<number> {
  const configurationId = requireValue(parsed.configurationId, "--configuration-id");
  const outputId = requireValue(parsed.outputId, "--output-id");

  await rm(outputPath(parsed.storeDir, configurationId, outputId), { force: true });
  io.stdout(`${JSON.stringify({ ok: true, configurationId, outputId, cleared: true })}\n`);
  return 0;
}

async function seedSource(parsed: ParsedArgs, io: DspProviderCliIo): Promise<number> {
  const sourceId = requireValue(parsed.sourceId, "--source-id");
  const channels = requireValue(parsed.channels, "--channels");
  const frames = requireValue(parsed.frames, "--frames");
  const value = parsed.value ?? defaultSeedValue;
  const payload = {
    sourceId,
    channels: Array.from({ length: channels }, (_unused, channel) =>
      Array.from({ length: frames }, (_sample, frame) => value / (channel + frame + 1))
    )
  };

  await writeJson(sourcePath(parsed.storeDir, sourceId), payload);
  io.stdout(`${JSON.stringify({ ok: true, sourceId, frames })}\n`);
  return 0;
}

function parsePayload(raw: string, operation: string, target: string): BufferPayload {
  if (!raw.trim()) {
    throw new Error(`${operation} for ${target} requires JSON on stdin`);
  }

  try {
    return JSON.parse(raw) as BufferPayload;
  } catch {
    throw new Error(`${operation} for ${target} received invalid JSON on stdin`);
  }
}

function normalizeRenderedPayload(
  payload: BufferPayload,
  outputId: string,
  channels: number,
  frames: number,
  expectedPeak: number
): BufferPayload {
  const normalized = normalizeBufferPayload(payload, outputId, channels, frames);
  const actualPeak = measurePeak(normalized.channels);

  if (Math.abs(actualPeak - expectedPeak) > peakTolerance) {
    throw new Error(`DSP output ${outputId} peak mismatch: expected ${expectedPeak}, got ${actualPeak}`);
  }

  return normalized;
}

function normalizeBufferPayload(
  payload: BufferPayload,
  target: string,
  channels: number,
  frames?: number
): BufferPayload {
  if (!Array.isArray(payload.channels) || payload.channels.length !== channels) {
    throw new Error(`DSP buffer ${target} must contain ${channels} channel(s)`);
  }

  return {
    channels: payload.channels.map((channel, channelIndex) =>
      normalizeChannel(channel, target, channelIndex, frames)
    )
  };
}

function normalizeChannel(
  channel: readonly number[],
  target: string,
  channelIndex: number,
  frames?: number
): readonly number[] {
  if (!Array.isArray(channel)) {
    throw new Error(`DSP buffer ${target} channel ${channelIndex} is not an array`);
  }

  if (frames !== undefined && channel.length < frames) {
    throw new Error(`DSP buffer ${target} channel ${channelIndex} has fewer than ${frames} frame(s)`);
  }

  const samples = frames === undefined ? channel : channel.slice(0, frames);

  for (const [frameIndex, sample] of samples.entries()) {
    if (typeof sample !== "number" || !Number.isFinite(sample)) {
      throw new Error(`DSP buffer ${target} has an invalid sample at ${channelIndex}:${frameIndex}`);
    }
  }

  return samples;
}

function buffersEqual(left: readonly (readonly number[])[], right: readonly (readonly number[])[]): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

function measurePeak(channels: readonly (readonly number[])[]): number {
  return channels.reduce(
    (peak, channel) => channel.reduce((innerPeak, sample) => Math.max(innerPeak, Math.abs(sample)), peak),
    0
  );
}

async function writeJson(path: string, payload: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(payload)}\n`, "utf8");
}

function sourcePath(storeDir: string, sourceId: string): string {
  return join(storeDir, "sources", `${safeId(sourceId)}.json`);
}

function outputPath(storeDir: string, configurationId: string, outputId: string): string {
  return join(storeDir, "outputs", safeId(configurationId), `${safeId(outputId)}.json`);
}

function safeId(value: string): string {
  if (!value || value.includes("/") || value.includes("\\") || value.includes("\0")) {
    throw new Error(`Unsafe DSP provider id: ${value}`);
  }

  return encodeURIComponent(value);
}

function defaultStoreDir(env: NodeJS.ProcessEnv): string {
  if (env.LOOPWIRE_DSP_PROVIDER_DIR) {
    return env.LOOPWIRE_DSP_PROVIDER_DIR;
  }

  return join(env.XDG_STATE_HOME ?? join(homedir(), ".local", "state"), "loopwire", "dsp-provider");
}

function isCommand(command: string): command is DspProviderCommand {
  const commands: readonly string[] = [
    "capabilities",
    "read-source",
    "write-output",
    "verify-output",
    "clear-output",
    "seed-source"
  ];

  return commands.includes(command);
}

function optionalPositiveInteger(value: string | undefined, label: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new Error(`${label} must be a positive integer`);
  }

  return Number(value);
}

function optionalFiniteNumber(value: string | undefined, label: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  const parsed = Number(value);

  if (!Number.isFinite(parsed)) {
    throw new Error(`${label} must be a finite number`);
  }

  return parsed;
}

function requireValue<T>(value: T | undefined, label: string): T {
  if (value === undefined || value === "") {
    throw new Error(`${label} is required`);
  }

  return value;
}

function isMissingFile(error: unknown): boolean {
  return Boolean(error && typeof error === "object" && (error as NodeJS.ErrnoException).code === "ENOENT");
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function usage(): string {
  return `Loopwire file-backed DSP provider.

Usage:
  loopwire-dsp-provider capabilities
  loopwire-dsp-provider read-source --source-id ID --channels N [--frames N] [--store-dir DIR]
  loopwire-dsp-provider write-output --output-id ID --channels N --frames N --peak VALUE --configuration-id ID [--store-dir DIR]
  loopwire-dsp-provider verify-output --output-id ID --channels N --frames N --peak VALUE --configuration-id ID [--store-dir DIR]
  loopwire-dsp-provider clear-output --configuration-id ID --output-id ID [--store-dir DIR]
  loopwire-dsp-provider seed-source --source-id ID --channels N --frames N [--value N] [--store-dir DIR]

State defaults to LOOPWIRE_DSP_PROVIDER_DIR or XDG_STATE_HOME/loopwire/dsp-provider.
capabilities prints provider metadata and declares supportsLiveGraph:false for this bundled file-backed provider.
read-source prints {"missing":true} until a source is seeded.
write-output and verify-output read Loopwire rendered-output JSON on stdin.
`;
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];

  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  return Buffer.concat(chunks).toString("utf8");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const exitCode = await runDspProviderCli(process.argv.slice(2), {
    env: process.env,
    stdin: await readStdin(),
    stdout: (text) => process.stdout.write(text),
    stderr: (text) => process.stderr.write(text)
  });

  process.exitCode = exitCode;
}
