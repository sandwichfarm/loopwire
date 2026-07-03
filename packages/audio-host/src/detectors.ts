import type {
  AudioBackendKind,
  AudioBackendDetectionReport,
  AudioInputSource,
  AudioInputSourceReport,
  AudioPlaybackDevice,
  AudioPlaybackDeviceReport,
  BackendCapabilityReport,
  BackendCandidate,
  BackendDiagnostic,
  BackendMixingSemantics,
  BackendOperations,
  CommandProbe,
  CommandResult,
  CommandRunner
} from "./types.js";

export type {
  AudioBackendDetectionReport,
  AudioInputSource,
  AudioInputSourceReport,
  AudioPlaybackDevice,
  AudioPlaybackDeviceReport
} from "./types.js";

const timeoutMs = 3500;

const plannedRoutingOperations: BackendOperations = {
  detect: "implemented",
  enumerateDevices: "implemented",
  createVirtualDevice: "planned",
  routeAudio: "planned",
  monitorAudio: "planned",
  apply: "planned",
  verify: "planned",
  rollback: "planned"
};

const pipeWireLinkOperations: BackendOperations = {
  detect: "implemented",
  enumerateDevices: "implemented",
  createVirtualDevice: "implemented",
  routeAudio: "implemented",
  monitorAudio: "implemented",
  apply: "implemented",
  verify: "implemented",
  rollback: "implemented"
};

const jackLinkOperations: BackendOperations = {
  detect: "implemented",
  enumerateDevices: "implemented",
  createVirtualDevice: "planned",
  routeAudio: "implemented",
  monitorAudio: "implemented",
  apply: "implemented",
  verify: "implemented",
  rollback: "implemented"
};

const pactlVirtualSinkOperations: BackendOperations = {
  detect: "implemented",
  enumerateDevices: "implemented",
  createVirtualDevice: "implemented",
  routeAudio: "implemented",
  monitorAudio: "implemented",
  apply: "implemented",
  verify: "implemented",
  rollback: "implemented"
};

const unavailableOperations: BackendOperations = {
  detect: "implemented",
  enumerateDevices: "unavailable",
  createVirtualDevice: "unavailable",
  routeAudio: "unavailable",
  monitorAudio: "unavailable",
  apply: "unavailable",
  verify: "unavailable",
  rollback: "unavailable"
};

const unavailableMixing: BackendMixingSemantics = {
  controlScope: "unavailable",
  supportsPerEdgeGain: false,
  supportsPerEdgeMute: false,
  warning: "No route controls are available because the backend is unavailable."
};

const pipeWireLinkMixing: BackendMixingSemantics = {
  controlScope: "link-only",
  supportsPerEdgeGain: false,
  supportsPerEdgeMute: true,
  warning: "Native PipeWire applies mute by disconnecting existing graph links; per-edge gain is not implemented."
};

const jackLinkMixing: BackendMixingSemantics = {
  controlScope: "link-only",
  supportsPerEdgeGain: false,
  supportsPerEdgeMute: true,
  warning: "Native JACK applies mute by disconnecting existing graph links; per-edge gain is not implemented."
};

const pulseStreamMixing: BackendMixingSemantics = {
  controlScope: "stream",
  supportsPerEdgeGain: false,
  supportsPerEdgeMute: false,
  warning: "PulseAudio compatibility applies gain and mute to whole matching streams, not individual graph edges."
};

const plannedGraphMixing: BackendMixingSemantics = {
  controlScope: "graph-edge",
  supportsPerEdgeGain: false,
  supportsPerEdgeMute: false,
  warning: "Graph-edge gain and mute controls are planned but not implemented for this backend."
};

export async function detectAudioBackends(
  runner: CommandRunner,
  now: Date = new Date(),
  platform: NodeJS.Platform = process.platform
): Promise<AudioBackendDetectionReport> {
  const reports = await Promise.all([
    detectPipeWire(runner),
    detectPulseAudio(runner),
    detectJack(runner),
    detectAlsa(runner)
  ]);

  return {
    generatedAt: now.toISOString(),
    platform,
    reports,
    candidates: toBackendCandidates(reports)
  };
}

export function toBackendCandidates(reports: readonly BackendCapabilityReport[]): readonly BackendCandidate[] {
  return reports.map((report) => ({
    kind: report.kind,
    displayName: report.displayName,
    availability: report.availability,
    priority: report.priority,
    ...(report.availability === "unavailable" ? { reason: primaryReason(report) } : {})
  }));
}

export async function enumeratePlaybackDevices(
  runner: CommandRunner,
  backend: AudioBackendKind,
  now: Date = new Date()
): Promise<AudioPlaybackDeviceReport> {
  if (backend === "pipewire") {
    return enumeratePipeWirePlaybackDevices(runner, backend, now);
  }

  if (backend === "jack") {
    return enumerateJackPlaybackDevices(runner, backend, now);
  }

  if (backend !== "pulseaudio") {
    return {
      generatedAt: now.toISOString(),
      backend,
      devices: [],
      diagnostics: [
        {
          level: "warning",
          code: "PLAYBACK_ENUMERATION_MANUAL",
          message: "Monitor target selection uses manual device names until this backend supports monitor routing."
        }
      ],
      commands: []
    };
  }

  const sinks = await runProbe(runner, "pactl", ["list", "short", "sinks"]);
  const commands = [toProbe(sinks)];

  if (sinks.exitCode !== 0) {
    return {
      generatedAt: now.toISOString(),
      backend,
      devices: [],
      diagnostics: unavailableDiagnostics("PLAYBACK_ENUMERATION_FAILED", commands, "Could not list PulseAudio sinks."),
      commands
    };
  }

  const devices = parsePactlShortSinks(sinks.stdout, backend);

  return {
    generatedAt: now.toISOString(),
    backend,
    devices,
    diagnostics:
      devices.length > 0
        ? [{ level: "info", code: "PLAYBACK_DEVICES_AVAILABLE", message: `Listed ${devices.length} playback sink(s).` }]
        : [{ level: "warning", code: "PLAYBACK_DEVICES_EMPTY", message: "PulseAudio returned no playback sinks." }],
    commands
  };
}

export async function enumerateInputSources(
  runner: CommandRunner,
  backend: AudioBackendKind,
  now: Date = new Date()
): Promise<AudioInputSourceReport> {
  if (backend === "pipewire") {
    return enumeratePipeWireInputSources(runner, backend, now);
  }

  if (backend === "jack") {
    return enumerateJackInputSources(runner, backend, now);
  }

  if (backend !== "pulseaudio") {
    return {
      generatedAt: now.toISOString(),
      backend,
      sources: [],
      diagnostics: [
        {
          level: "warning",
          code: "INPUT_SOURCE_ENUMERATION_MANUAL",
          message: "Source selection uses static and manual candidates until this backend supports stream enumeration."
        }
      ],
      commands: []
    };
  }

  const sinkInputs = await runProbe(runner, "pactl", ["list", "sink-inputs"]);
  const commands = [toProbe(sinkInputs)];

  if (sinkInputs.exitCode !== 0) {
    return {
      generatedAt: now.toISOString(),
      backend,
      sources: [],
      diagnostics: unavailableDiagnostics("INPUT_SOURCE_ENUMERATION_FAILED", commands, "Could not list PulseAudio streams."),
      commands
    };
  }

  const sources = parsePactlSinkInputSources(sinkInputs.stdout, backend);

  return {
    generatedAt: now.toISOString(),
    backend,
    sources,
    diagnostics:
      sources.length > 0
        ? [{ level: "info", code: "INPUT_SOURCES_AVAILABLE", message: `Listed ${sources.length} running source stream(s).` }]
        : [{ level: "warning", code: "INPUT_SOURCES_EMPTY", message: "PulseAudio returned no running source streams." }],
    commands
  };
}

async function enumeratePipeWirePlaybackDevices(
  runner: CommandRunner,
  backend: AudioBackendKind,
  now: Date
): Promise<AudioPlaybackDeviceReport> {
  const ports = await runProbe(runner, "pw-link", ["-i"]);
  const commands = [toProbe(ports)];

  if (ports.exitCode !== 0) {
    return {
      generatedAt: now.toISOString(),
      backend,
      devices: [],
      diagnostics: unavailableDiagnostics("PLAYBACK_ENUMERATION_FAILED", commands, "Could not list PipeWire input ports."),
      commands
    };
  }

  const devices = parsePipeWirePlaybackDevices(ports.stdout, backend);

  return {
    generatedAt: now.toISOString(),
    backend,
    devices,
    diagnostics:
      devices.length > 0
        ? [{ level: "info", code: "PLAYBACK_DEVICES_AVAILABLE", message: `Listed ${devices.length} playback sink(s).` }]
        : [{ level: "warning", code: "PLAYBACK_DEVICES_EMPTY", message: "PipeWire returned no input ports." }],
    commands
  };
}

async function enumeratePipeWireInputSources(
  runner: CommandRunner,
  backend: AudioBackendKind,
  now: Date
): Promise<AudioInputSourceReport> {
  const ports = await runProbe(runner, "pw-link", ["-o"]);
  const commands = [toProbe(ports)];

  if (ports.exitCode !== 0) {
    return {
      generatedAt: now.toISOString(),
      backend,
      sources: [],
      diagnostics: unavailableDiagnostics("INPUT_SOURCE_ENUMERATION_FAILED", commands, "Could not list PipeWire output ports."),
      commands
    };
  }

  const sources = parsePipeWireInputSources(ports.stdout, backend);

  return {
    generatedAt: now.toISOString(),
    backend,
    sources,
    diagnostics:
      sources.length > 0
        ? [{ level: "info", code: "INPUT_SOURCES_AVAILABLE", message: `Listed ${sources.length} output source(s).` }]
        : [{ level: "warning", code: "INPUT_SOURCES_EMPTY", message: "PipeWire returned no output ports." }],
    commands
  };
}

async function enumerateJackPlaybackDevices(
  runner: CommandRunner,
  backend: AudioBackendKind,
  now: Date
): Promise<AudioPlaybackDeviceReport> {
  const ports = await runProbe(runner, "jack_lsp", ["-p"]);
  const commands = [toProbe(ports)];

  if (ports.exitCode !== 0) {
    return {
      generatedAt: now.toISOString(),
      backend,
      devices: [],
      diagnostics: unavailableDiagnostics("PLAYBACK_ENUMERATION_FAILED", commands, "Could not list JACK ports."),
      commands
    };
  }

  const devices = parseJackPlaybackDevices(ports.stdout, backend);

  return {
    generatedAt: now.toISOString(),
    backend,
    devices,
    diagnostics:
      devices.length > 0
        ? [{ level: "info", code: "PLAYBACK_DEVICES_AVAILABLE", message: `Listed ${devices.length} JACK input target(s).` }]
        : [{ level: "warning", code: "PLAYBACK_DEVICES_EMPTY", message: "JACK returned no input ports." }],
    commands
  };
}

async function enumerateJackInputSources(
  runner: CommandRunner,
  backend: AudioBackendKind,
  now: Date
): Promise<AudioInputSourceReport> {
  const ports = await runProbe(runner, "jack_lsp", ["-p"]);
  const commands = [toProbe(ports)];

  if (ports.exitCode !== 0) {
    return {
      generatedAt: now.toISOString(),
      backend,
      sources: [],
      diagnostics: unavailableDiagnostics("INPUT_SOURCE_ENUMERATION_FAILED", commands, "Could not list JACK ports."),
      commands
    };
  }

  const sources = parseJackInputSources(ports.stdout, backend);

  return {
    generatedAt: now.toISOString(),
    backend,
    sources,
    diagnostics:
      sources.length > 0
        ? [{ level: "info", code: "INPUT_SOURCES_AVAILABLE", message: `Listed ${sources.length} JACK output source(s).` }]
        : [{ level: "warning", code: "INPUT_SOURCES_EMPTY", message: "JACK returned no output ports." }],
    commands
  };
}

async function detectPipeWire(runner: CommandRunner): Promise<BackendCapabilityReport> {
  const version = await runProbe(runner, "pw-cli", ["--version"]);
  const status = await runProbe(runner, "wpctl", ["status"]);
  const fallbackInfo = status.exitCode === 0 ? undefined : await runProbe(runner, "pw-cli", ["info", "0"]);
  const available = status.exitCode === 0 || fallbackInfo?.exitCode === 0;
  const commands = compact([version, status, fallbackInfo]).map(toProbe);
  const parsedVersion =
    parsePipeWireVersion(status.stdout) ?? parsePipeWireVersion(version.stdout) ?? firstLine(version.stdout) ?? firstLine(status.stdout);

  return {
    kind: "pipewire",
    displayName: "PipeWire",
    availability: available ? "available" : "unavailable",
    priority: 10,
    transport: "native",
    ...(parsedVersion ? { version: parsedVersion } : {}),
    operations: available ? pipeWireLinkOperations : unavailableOperations,
    mixing: available ? pipeWireLinkMixing : unavailableMixing,
    gaps: available ? ["per-edge gain controls"] : ["service unavailable"],
    diagnostics: available
      ? [{ level: "info", code: "PIPEWIRE_AVAILABLE", message: "PipeWire service responded to a read-only probe." }]
      : unavailableDiagnostics("PIPEWIRE_UNAVAILABLE", commands, "PipeWire tools or service are not available."),
    commands
  };
}

async function detectPulseAudio(runner: CommandRunner): Promise<BackendCapabilityReport> {
  const info = await runProbe(runner, "pactl", ["info"]);
  const serverName = parsePactlField(info.stdout, "Server Name");
  const serverVersion = parsePactlField(info.stdout, "Server Version");
  const available = info.exitCode === 0;
  const pipewireCompat = Boolean(serverName?.toLowerCase().includes("pipewire"));
  const displayName = pipewireCompat ? "PulseAudio Compatibility" : "PulseAudio";

  return {
    kind: "pulseaudio",
    displayName,
    availability: available ? "available" : "unavailable",
    priority: pipewireCompat ? 25 : 20,
    transport: "compatibility",
    ...(serverName ? { serverName } : {}),
    ...(serverVersion ? { version: serverVersion } : {}),
    operations: available ? pactlVirtualSinkOperations : unavailableOperations,
    mixing: available ? pulseStreamMixing : unavailableMixing,
    gaps: available ? ["true per-edge mixing beyond sink-input controls"] : ["service unavailable"],
    diagnostics: available
      ? [
          {
            level: "info",
            code: pipewireCompat ? "PULSE_PIPEWIRE_COMPAT" : "PULSEAUDIO_AVAILABLE",
            message: pipewireCompat
              ? "PulseAudio API is provided through PipeWire compatibility."
              : "PulseAudio server responded to pactl."
          }
        ]
      : unavailableDiagnostics("PULSEAUDIO_UNAVAILABLE", [toProbe(info)], "PulseAudio pactl probe did not succeed."),
    commands: [toProbe(info)]
  };
}

async function detectJack(runner: CommandRunner): Promise<BackendCapabilityReport> {
  const ports = await runProbe(runner, "jack_lsp", []);
  const available = ports.exitCode === 0;

  return {
    kind: "jack",
    displayName: "JACK",
    availability: available ? "available" : "unavailable",
    priority: 30,
    transport: "bridge",
    operations: available ? jackLinkOperations : unavailableOperations,
    mixing: available ? jackLinkMixing : unavailableMixing,
    gaps: available
      ? ["virtual device creation", "virtual monitor sink creation", "per-edge gain controls"]
      : ["server unavailable"],
    diagnostics: available
      ? [{ level: "info", code: "JACK_AVAILABLE", message: "JACK server returned a port listing; existing-port routing is available." }]
      : unavailableDiagnostics("JACK_UNAVAILABLE", [toProbe(ports)], "JACK tools or server are not available."),
    commands: [toProbe(ports)]
  };
}

async function detectAlsa(runner: CommandRunner): Promise<BackendCapabilityReport> {
  const devices = await runProbe(runner, "aplay", ["-l"]);
  const hasCards = /(^|\n)card\s+\d+:/i.test(devices.stdout);
  const available = devices.exitCode === 0 && hasCards;

  return {
    kind: "alsa",
    displayName: "ALSA",
    availability: available ? "available" : "unavailable",
    priority: 40,
    transport: "hardware",
    operations: available
      ? {
          ...plannedRoutingOperations,
          createVirtualDevice: "unavailable",
          routeAudio: "planned"
        }
      : unavailableOperations,
    mixing: available ? plannedGraphMixing : unavailableMixing,
    gaps: available ? ["virtual device creation requires higher-level backend", "route apply", "verify", "rollback"] : ["no playback devices"],
    diagnostics: available
      ? [{ level: "info", code: "ALSA_DEVICES_AVAILABLE", message: "ALSA playback devices were listed." }]
      : unavailableDiagnostics("ALSA_UNAVAILABLE", [toProbe(devices)], "ALSA playback devices were not listed."),
    commands: [toProbe(devices)]
  };
}

async function runProbe(runner: CommandRunner, command: string, args: readonly string[]): Promise<CommandResult> {
  return runner.run(command, args, { timeoutMs });
}

function toProbe(result: CommandResult): CommandProbe {
  return {
    command: result.command,
    args: result.args,
    exitCode: result.exitCode,
    available: result.exitCode === 0,
    summary: summarizeCommand(result)
  };
}

function summarizeCommand(result: CommandResult): string {
  if (result.errorCode === "missing") {
    return "command missing";
  }

  if (result.errorCode === "timeout") {
    return "command timed out";
  }

  if (result.exitCode !== 0) {
    return firstLine(result.stderr) || `exit ${result.exitCode}`;
  }

  return redactSummary(firstLine(result.stdout) || "ok");
}

function unavailableDiagnostics(
  code: string,
  commands: readonly CommandProbe[],
  fallbackMessage: string
): readonly BackendDiagnostic[] {
  const commandReason = commands.find((command) => !command.available)?.summary;

  return [
    {
      level: "warning",
      code,
      message: commandReason ? `${fallbackMessage} Probe result: ${commandReason}.` : fallbackMessage
    }
  ];
}

function primaryReason(report: BackendCapabilityReport): string {
  return report.diagnostics.find((diagnostic) => diagnostic.level !== "info")?.message ?? `${report.displayName} is unavailable.`;
}

function parsePactlField(output: string, field: string): string | undefined {
  const prefix = `${field}:`;
  const line = output.split(/\r?\n/).find((item) => item.startsWith(prefix));
  return line?.slice(prefix.length).trim() || undefined;
}

function parsePipeWireVersion(output: string): string | undefined {
  const bracketVersion = output.match(/PipeWire[^\[]*\[([0-9][^,\]\s]*)/i)?.[1];
  const libraryVersion = output.match(/libpipewire\s+([0-9][^\s]*)/i)?.[1];
  return bracketVersion ?? libraryVersion;
}

function parsePactlShortSinks(output: string, backend: AudioBackendKind): readonly AudioPlaybackDevice[] {
  return output
    .split(/\r?\n/)
    .map((line) => parsePactlShortSink(line, backend))
    .filter((device): device is AudioPlaybackDevice => device !== undefined);
}

function parsePactlShortSink(line: string, backend: AudioBackendKind): AudioPlaybackDevice | undefined {
  const columns = line.split("\t").map((column) => column.trim());
  const deviceName = columns[1];

  if (!deviceName) {
    return undefined;
  }

  return {
    backend,
    deviceName,
    label: labelFromDeviceName(deviceName),
    ...(columns[4] || columns[3] ? { detail: compact([columns[4], columns[3]]).join(" - ") } : {})
  };
}

function parsePipeWirePlaybackDevices(output: string, backend: AudioBackendKind): readonly AudioPlaybackDevice[] {
  return parsePipeWirePortGroups(output).map((group) => ({
    backend,
    deviceName: group.deviceName,
    label: labelFromDeviceName(group.deviceName),
    detail: `${group.portCount} input port(s)`
  }));
}

function parsePipeWireInputSources(output: string, backend: AudioBackendKind): readonly AudioInputSource[] {
  return parsePipeWirePortGroups(output).map((group) => ({
    backend,
    sourceId: slugifySourceId(group.deviceName),
    sourceName: group.deviceName,
    label: labelFromDeviceName(group.deviceName),
    detail: `${group.portCount} output port(s)`,
    channels: group.portCount
  }));
}

function parsePipeWirePortGroups(output: string): readonly {
  readonly deviceName: string;
  readonly portCount: number;
}[] {
  const groups = new Map<string, number>();

  for (const line of output.split(/\r?\n/)) {
    const portName = line.trim();

    if (!portName || portName.startsWith("|")) {
      continue;
    }

    const deviceName = portName.split(":", 1)[0]?.trim() || portName;
    groups.set(deviceName, (groups.get(deviceName) ?? 0) + 1);
  }

  return Array.from(groups, ([deviceName, portCount]) => ({ deviceName, portCount }));
}

function parseJackPlaybackDevices(output: string, backend: AudioBackendKind): readonly AudioPlaybackDevice[] {
  return parseJackPortGroups(output, "input").map((group) => ({
    backend,
    deviceName: group.deviceName,
    label: labelFromDeviceName(group.deviceName),
    detail: `${group.portCount} input port(s)`
  }));
}

function parseJackInputSources(output: string, backend: AudioBackendKind): readonly AudioInputSource[] {
  return parseJackPortGroups(output, "output").map((group) => ({
    backend,
    sourceId: slugifySourceId(group.deviceName),
    sourceName: group.deviceName,
    label: labelFromDeviceName(group.deviceName),
    detail: `${group.portCount} output port(s)`,
    channels: group.portCount
  }));
}

function parseJackPortGroups(
  output: string,
  direction: "input" | "output"
): readonly {
  readonly deviceName: string;
  readonly portCount: number;
}[] {
  const groups = new Map<string, number>();
  let currentPort: string | undefined;

  for (const line of output.split(/\r?\n/)) {
    const trimmed = line.trim();

    if (!trimmed) {
      continue;
    }

    if (!/^\s/.test(line)) {
      currentPort = trimmed;
      continue;
    }

    if (!currentPort || !trimmed.toLowerCase().startsWith("properties:")) {
      continue;
    }

    const properties = trimmed.slice("properties:".length).split(",").map((item) => item.trim().toLowerCase());
    if (!properties.includes(direction)) {
      continue;
    }

    const deviceName = currentPort.split(":", 1)[0]?.trim() || currentPort;
    groups.set(deviceName, (groups.get(deviceName) ?? 0) + 1);
  }

  return Array.from(groups, ([deviceName, portCount]) => ({ deviceName, portCount }));
}

function parsePactlSinkInputSources(output: string, backend: AudioBackendKind): readonly AudioInputSource[] {
  return output
    .split(/\r?\n(?=Sink Input #)/)
    .map((block) => parsePactlSinkInputSource(block, backend))
    .filter((source): source is AudioInputSource => source !== undefined);
}

function parsePactlSinkInputSource(block: string, backend: AudioBackendKind): AudioInputSource | undefined {
  const sinkInputId = block.match(/Sink Input #(\d+)/)?.[1];

  if (!sinkInputId) {
    return undefined;
  }

  const appName = parsePactlProperty(block, "application.name");
  const mediaName = parsePactlProperty(block, "media.name");
  const binaryName = parsePactlProperty(block, "application.process.binary");
  const sinkName = block.match(/^\s*Sink:\s+([^\s]+)/m)?.[1];
  const channels = Number.parseInt(block.match(/^\s*Sample Specification:.*?\s([0-9]+)ch\s/im)?.[1] ?? "", 10);
  const label = appName ?? mediaName ?? binaryName ?? `Sink Input ${sinkInputId}`;
  const sourceName = binaryName ?? appName ?? mediaName ?? `sink-input-${sinkInputId}`;
  const detail = compact([
    mediaName && !sameText(mediaName, label) ? mediaName : undefined,
    binaryName && !sameText(binaryName, label) ? binaryName : undefined,
    sinkName ? `Sink ${sinkName}` : undefined
  ]).join(" - ");

  return {
    backend,
    sourceId: slugifySourceId(`${sourceName}-${sinkInputId}`),
    sourceName,
    label,
    ...(detail ? { detail } : {}),
    channels: Number.isFinite(channels) ? channels : 2
  };
}

function parsePactlProperty(block: string, key: string): string | undefined {
  const prefix = `${key} = `;
  const line = block
    .split(/\r?\n/)
    .map((item) => item.trim())
    .find((item) => item.startsWith(prefix));
  const value = line?.slice(prefix.length).trim();

  if (!value) {
    return undefined;
  }

  if (value.startsWith("\"") && value.endsWith("\"")) {
    return value.slice(1, -1).replace(/\\"/g, "\"").trim() || undefined;
  }

  return value;
}

function sameText(left: string, right: string): boolean {
  return left.localeCompare(right, undefined, { sensitivity: "accent" }) === 0;
}

function slugifySourceId(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64) || "source";
}

function labelFromDeviceName(deviceName: string): string {
  const withoutPrefix = deviceName.replace(/^(alsa|bluez|jack|pipewire)_(input|output)[._-]?/i, "");
  const readable = withoutPrefix.replace(/[._-]+/g, " ").trim();
  return readable || deviceName;
}

function firstLine(output: string): string | undefined {
  return output.split(/\r?\n/).map((line) => line.trim()).find(Boolean);
}

function redactSummary(summary: string): string {
  return summary
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9._-]+/g, "<user@host>")
    .replace(/\/run\/user\/[0-9]+/g, "/run/user/<uid>")
    .replace(/pid:[0-9]+/g, "pid:<redacted>")
    .replace(/cookie:[0-9]+/g, "cookie:<redacted>");
}

function compact<T>(items: readonly (T | undefined)[]): T[] {
  return items.filter((item): item is T => item !== undefined);
}
