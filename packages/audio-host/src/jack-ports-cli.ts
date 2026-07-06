#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

type JackPortsCommand = "ensure";
type JackPortsDelegateMode = "foreground" | "detached";

interface JackPortsCliIo {
  readonly env?: NodeJS.ProcessEnv;
  stdout(text: string): void;
  stderr(text: string): void;
}

interface ParsedArgs {
  readonly command: JackPortsCommand | undefined;
  readonly configurationId: string | undefined;
  readonly requirements: readonly JackPortProviderRequirement[];
  readonly missingPorts: readonly string[];
  readonly manifestFile: string | undefined;
  readonly delegateCommand: string | undefined;
  readonly delegateMode: JackPortsDelegateMode;
  readonly readyDelayMs: number;
}

interface JackPortProviderRequirement {
  readonly kind: string;
  readonly source: string;
  readonly endpointId: string;
  readonly deviceName: string;
  readonly channelCount: number;
}

const delegateEnv = "LOOPWIRE_JACK_PORTS_DELEGATE";
const delegateModeEnv = "LOOPWIRE_JACK_PORTS_DELEGATE_MODE";
const manifestEnv = "LOOPWIRE_JACK_PORTS_MANIFEST";
const readyDelayMsEnv = "LOOPWIRE_JACK_PORTS_READY_DELAY_MS";
const defaultReadyDelayMs = 250;

export async function runJackPortsCli(argv: readonly string[], io: JackPortsCliIo): Promise<number> {
  try {
    const normalizedArgv = normalizeArgv(argv);
    const parsed = parseArgs(normalizedArgv, io.env ?? process.env);

    if (!parsed.command) {
      io.stdout(usage());
      return 0;
    }

    await writeProvisionManifest(parsed);

    if (!parsed.delegateCommand) {
      io.stderr(
        [
          "loopwire-jack-ports recorded the requested JACK virtual ports but did not create live JACK clients.",
          `Set ${delegateEnv} to a live JACK provider command before using this command for live restore.`
        ].join(" ")
      );
      io.stderr("\n");
      return 2;
    }

    return parsed.delegateMode === "detached"
      ? await delegateDetached(parsed, normalizedArgv, io)
      : await delegateEnsure(parsed, normalizedArgv, io);
  } catch (error) {
    io.stderr(`${errorMessage(error)}\n`);
    return 2;
  }
}

function normalizeArgv(argv: readonly string[]): readonly string[] {
  return argv[0] === "--" ? argv.slice(1) : argv;
}

function parseArgs(argv: readonly string[], env: NodeJS.ProcessEnv): ParsedArgs {
  const command = argv[0];

  if (command === "-h" || command === "--help" || command === undefined) {
    return emptyArgs(env);
  }

  if (command !== "ensure") {
    throw new Error(`Unknown JACK ports command: ${command}`);
  }

  let configurationId: string | undefined;
  let manifestFile = env[manifestEnv];
  let delegateCommand = env[delegateEnv];
  let delegateMode = parseDelegateMode(env[delegateModeEnv] ?? "foreground");
  let readyDelayMs = parseReadyDelayMs(env[readyDelayMsEnv] ?? String(defaultReadyDelayMs));
  const requirements: JackPortProviderRequirement[] = [];
  const missingPorts: string[] = [];

  for (let index = 1; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];

    if (!flag?.startsWith("--")) {
      throw new Error(`Unknown JACK ports argument: ${flag ?? ""}`);
    }

    if (!value || value.startsWith("--")) {
      throw new Error(`${flag} requires a value`);
    }

    switch (flag) {
      case "--configuration-id":
        configurationId = value;
        break;
      case "--requirement":
        requirements.push(parseRequirement(value));
        break;
      case "--port":
        missingPorts.push(validatePort(value));
        break;
      case "--manifest-file":
        manifestFile = value;
        break;
      case "--delegate-command":
        delegateCommand = value;
        break;
      case "--delegate-mode":
        delegateMode = parseDelegateMode(value);
        break;
      case "--ready-delay-ms":
        readyDelayMs = parseReadyDelayMs(value);
        break;
      default:
        throw new Error(`Unknown JACK ports argument: ${flag}`);
    }

    index += 1;
  }

  if (!configurationId) {
    throw new Error("--configuration-id is required");
  }

  if (requirements.length === 0) {
    throw new Error("At least one --requirement is required");
  }

  if (missingPorts.length === 0) {
    throw new Error("At least one --port is required");
  }

  return {
    command,
    configurationId,
    requirements,
    missingPorts: uniqueSorted(missingPorts),
    manifestFile: manifestFile ?? defaultManifestFile(env),
    delegateCommand,
    delegateMode,
    readyDelayMs
  };
}

function emptyArgs(env: NodeJS.ProcessEnv): ParsedArgs {
  return {
    command: undefined,
    configurationId: undefined,
    requirements: [],
    missingPorts: [],
    manifestFile: env[manifestEnv] ?? defaultManifestFile(env),
    delegateCommand: env[delegateEnv],
    delegateMode: parseDelegateMode(env[delegateModeEnv] ?? "foreground"),
    readyDelayMs: parseReadyDelayMs(env[readyDelayMsEnv] ?? String(defaultReadyDelayMs))
  };
}

function parseRequirement(value: string): JackPortProviderRequirement {
  const [kind, source, endpointId, deviceName, channelText, extra] = value.split(":");

  if (extra !== undefined || !kind || !source || !endpointId || !deviceName || !channelText) {
    throw new Error(`Invalid --requirement value: ${value}`);
  }

  return {
    kind,
    source,
    endpointId,
    deviceName,
    channelCount: parsePositiveInteger(channelText, "--requirement channel count")
  };
}

function validatePort(value: string): string {
  if (!value || value.includes("\0") || value.includes("\n") || value.includes("\r")) {
    throw new Error(`Invalid JACK port name: ${value}`);
  }

  return value;
}

async function writeProvisionManifest(parsed: ParsedArgs): Promise<void> {
  if (!parsed.manifestFile) {
    return;
  }

  const payload = {
    kind: "loopwire.jack-ports.provision-plan",
    version: 1,
    configurationId: parsed.configurationId,
    requirements: parsed.requirements,
    missingPorts: parsed.missingPorts,
    delegateCommand: parsed.delegateCommand ?? null,
    delegateMode: parsed.delegateCommand ? parsed.delegateMode : null,
    readyDelayMs: parsed.readyDelayMs
  };

  await mkdir(dirname(parsed.manifestFile), { recursive: true });
  await writeFile(parsed.manifestFile, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function delegateEnsure(parsed: ParsedArgs, originalArgv: readonly string[], io: JackPortsCliIo): Promise<number> {
  return new Promise((resolve) => {
    const child = spawn(parsed.delegateCommand ?? "", delegateArgv(originalArgv), {
      env: { ...process.env, ...(io.env ?? {}) },
      stdio: ["ignore", "pipe", "pipe"]
    });
    let settled = false;

    const finish = (code: number): void => {
      if (settled) {
        return;
      }

      settled = true;
      resolve(code);
    };

    child.stdout.on("data", (chunk: Buffer) => io.stdout(chunk.toString("utf8")));
    child.stderr.on("data", (chunk: Buffer) => io.stderr(chunk.toString("utf8")));
    child.on("error", (error: NodeJS.ErrnoException) => {
      io.stderr(`Could not run JACK delegate provider: ${error.message}\n`);
      finish(error.code === "ENOENT" ? 127 : 1);
    });
    child.on("close", (code) => finish(code ?? 1));
  });
}

function delegateDetached(parsed: ParsedArgs, originalArgv: readonly string[], io: JackPortsCliIo): Promise<number> {
  return new Promise((resolve) => {
    const child = spawn(parsed.delegateCommand ?? "", delegateArgv(originalArgv), {
      detached: true,
      env: { ...process.env, ...(io.env ?? {}) },
      stdio: "ignore"
    });
    let settled = false;
    let readyTimer: NodeJS.Timeout | undefined;

    const finish = (code: number): void => {
      if (settled) {
        return;
      }

      settled = true;
      if (readyTimer) {
        clearTimeout(readyTimer);
      }
      resolve(code);
    };

    child.on("error", (error: NodeJS.ErrnoException) => {
      io.stderr(`Could not start detached JACK delegate provider: ${error.message}\n`);
      finish(error.code === "ENOENT" ? 127 : 1);
    });
    child.on("exit", (code, signal) => {
      io.stderr(
        `Detached JACK delegate provider exited before readiness delay: ${exitDescription(code, signal)}\n`
      );
      finish(code ?? 1);
    });

    readyTimer = setTimeout(() => {
      child.removeAllListeners("exit");
      child.unref();
      io.stdout(
        `started detached JACK delegate provider pid ${child.pid} after ${parsed.readyDelayMs}ms readiness delay\n`
      );
      finish(0);
    }, parsed.readyDelayMs);
  });
}

function delegateArgv(argv: readonly string[]): readonly string[] {
  const forwarded: string[] = [];
  const wrapperOnlyFlags = new Set(["--delegate-command", "--delegate-mode", "--ready-delay-ms"]);

  for (let index = 0; index < argv.length; index += 1) {
    if (wrapperOnlyFlags.has(argv[index] ?? "")) {
      index += 1;
      continue;
    }

    forwarded.push(argv[index] ?? "");
  }

  return forwarded;
}

function defaultManifestFile(env: NodeJS.ProcessEnv): string {
  return join(
    env.XDG_STATE_HOME ?? join(homedir(), ".local", "state"),
    "loopwire",
    "jack-ports-provision.json"
  );
}

function parsePositiveInteger(value: string, label: string): number {
  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new Error(`${label} must be a positive integer`);
  }

  return Number(value);
}

function parseReadyDelayMs(value: string): number {
  if (!/^(0|[1-9][0-9]*)$/.test(value)) {
    throw new Error("--ready-delay-ms must be a non-negative integer");
  }

  return Number(value);
}

function parseDelegateMode(value: string): JackPortsDelegateMode {
  if (value !== "foreground" && value !== "detached") {
    throw new Error("--delegate-mode must be foreground or detached");
  }

  return value;
}

function uniqueSorted(values: readonly string[]): readonly string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function exitDescription(code: number | null, signal: NodeJS.Signals | null): string {
  if (code !== null) {
    return `exit ${code}`;
  }

  return signal ? `signal ${signal}` : "unknown exit";
}

function usage(): string {
  return `Loopwire JACK virtual port provider wrapper.

Usage:
  loopwire-jack-ports ensure --configuration-id ID --requirement KIND:SOURCE:ENDPOINT:DEVICE:CHANNELS --port PORT...

Options:
  --manifest-file FILE       Record the provision plan. Defaults to XDG_STATE_HOME/loopwire/jack-ports-provision.json.
  --delegate-command COMMAND Delegate live JACK client creation to COMMAND.
  --delegate-mode MODE       foreground (default) waits for COMMAND; detached keeps a long-running provider alive.
  --ready-delay-ms MS        Detached mode readiness delay before returning success. Default: ${defaultReadyDelayMs}.

Environment:
  LOOPWIRE_JACK_PORTS_MANIFEST   Default manifest path.
  LOOPWIRE_JACK_PORTS_DELEGATE   Live provider command used when --delegate-command is omitted.
  LOOPWIRE_JACK_PORTS_DELEGATE_MODE
                                  Default delegate mode: foreground or detached.
  LOOPWIRE_JACK_PORTS_READY_DELAY_MS
                                  Default detached readiness delay in milliseconds.

The bundled command never pretends to create JACK clients by itself. Without a delegate it records the exact plan and
exits nonzero so live restore fails closed with an actionable message. Detached mode is for live JACK providers that
must keep running for their ports to exist; Loopwire still re-runs jack_lsp after this wrapper returns.
`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const exitCode = await runJackPortsCli(process.argv.slice(2), {
    env: process.env,
    stdout: (text) => process.stdout.write(text),
    stderr: (text) => process.stderr.write(text)
  });

  process.exitCode = exitCode;
}
