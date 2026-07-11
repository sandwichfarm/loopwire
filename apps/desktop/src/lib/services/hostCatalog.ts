import { writable } from "svelte/store";
import {
  enumerateInputSources,
  enumeratePlaybackDevices,
  type AudioInputSource,
  type AudioPlaybackDevice,
  type AudioSourceKind
} from "@loopwire/audio-host/detectors";
import type { AudioBackendKind } from "@loopwire/core";
import { createTauriCommandRunner } from "./commandRunner";
import { hasTauriRuntime } from "./statePersistence";

export interface SourceCatalogEntry {
  readonly id: string;
  readonly label: string;
  readonly detail: string;
  readonly channels: number;
  readonly deviceName?: string;
  /** Enumeration kind; absent when the probe could not classify the source. */
  readonly kind?: AudioSourceKind;
  readonly category: string;
}

export interface MonitorCatalogEntry {
  readonly id: string;
  readonly label: string;
  readonly detail: string;
  readonly channels: number;
  readonly deviceName?: string;
}

/** Browser-preview sample candidates; the desktop shell enumerates real hosts. */
const sampleSources: readonly SourceCatalogEntry[] = [
  { id: "browser", kind: "app", category: "Running Applications", label: "Browser", detail: "Sample stream", channels: 2 },
  { id: "meeting-app", kind: "app", category: "Running Applications", label: "Meeting App", detail: "Sample stream", channels: 2 },
  { id: "system", kind: "system", category: "System Sources", label: "System Sounds", detail: "Desktop events", channels: 2 },
  { id: "mic", kind: "capture", category: "Capture Devices", label: "Studio Microphone", detail: "Hardware input", channels: 2 }
];

const sampleMonitors: readonly MonitorCatalogEntry[] = [
  { id: "headphones", label: "Headphones", detail: "Sample playback device", channels: 2 },
  { id: "speakers", label: "Speakers", detail: "Sample playback device", channels: 2 }
];

export function createHostCatalog() {
  const sources = writable<readonly SourceCatalogEntry[]>(sampleSources);
  const monitors = writable<readonly MonitorCatalogEntry[]>(sampleMonitors);
  const sourceNote = writable("Browser preview shows sample streams; the desktop shell lists real running apps.");
  const monitorNote = writable("Browser preview shows sample playback devices; the desktop shell lists real sinks.");

  async function refresh(backend: AudioBackendKind | undefined): Promise<void> {
    if (!hasTauriRuntime()) {
      return;
    }

    if (!backend) {
      sources.set([]);
      monitors.set([]);
      sourceNote.set("Choose an audio backend in Settings to list running app streams.");
      monitorNote.set("Choose an audio backend in Settings to list playback devices.");
      return;
    }

    const runner = createTauriCommandRunner();

    try {
      const report = await enumerateInputSources(runner, backend, new Date());
      sources.set(report.sources.map(toSourceEntry));
      sourceNote.set(
        report.sources.length > 0
          ? `Detected ${report.sources.length} source(s).`
          : (report.diagnostics[0]?.message ?? "No running app streams were listed.")
      );
    } catch (error) {
      sources.set([]);
      sourceNote.set(error instanceof Error ? `Could not list input sources: ${error.message}` : "Could not list input sources.");
    }

    try {
      const report = await enumeratePlaybackDevices(runner, backend, new Date());
      monitors.set(report.devices.map(toMonitorEntry));
      monitorNote.set(
        report.devices.length > 0
          ? `Detected ${report.devices.length} playback device(s).`
          : (report.diagnostics[0]?.message ?? "No playback devices were listed.")
      );
    } catch (error) {
      monitors.set([]);
      monitorNote.set(
        error instanceof Error ? `Could not list playback devices: ${error.message}` : "Could not list playback devices."
      );
    }
  }

  return { sources, monitors, sourceNote, monitorNote, refresh };
}

export type HostCatalog = ReturnType<typeof createHostCatalog>;

function toSourceEntry(source: AudioInputSource): SourceCatalogEntry {
  return {
    id: source.sourceId,
    label: source.label,
    detail: source.detail ?? source.sourceName,
    channels: source.channels,
    deviceName: source.sourceName,
    ...(source.kind ? { kind: source.kind } : {}),
    category: sourceCategory(source)
  };
}

function toMonitorEntry(device: AudioPlaybackDevice): MonitorCatalogEntry {
  return {
    id: `monitor-${device.deviceName}`,
    label: device.label,
    detail: device.detail ? `${device.deviceName} - ${device.detail}` : device.deviceName,
    channels: 2,
    deviceName: device.deviceName
  };
}

/** Category names derive from the enumeration kind; backend naming is only a fallback for unclassified sources. */
function sourceCategory(source: AudioInputSource): string {
  if (source.kind === "app") {
    return "Running Applications";
  }

  if (source.kind === "capture") {
    return "Capture Devices";
  }

  if (source.kind === "system") {
    return "System Sources";
  }

  if (source.backend === "jack") {
    return "JACK Ports";
  }

  if (source.backend === "alsa") {
    return "Capture Devices";
  }

  return "Running Applications";
}
