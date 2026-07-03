import { describe, expect, it } from "vitest";
import {
  activateConfiguration,
  addInputSourceToConfiguration,
  addMonitorToConfiguration,
  addOutputBusToConfiguration,
  addRouteToConfiguration,
  createDefaultState,
  createConfiguration,
  deleteConfiguration,
  duplicateConfiguration,
  getActiveConfiguration,
  getConfigurationById,
  getVisibleMonitors,
  isMonitorHidden,
  removeInputSourceFromConfiguration,
  removeMonitorFromConfiguration,
  removeOutputBusFromConfiguration,
  removeRouteFromConfiguration,
  setEndpointDeviceName,
  setMonitorHidden,
  setRouteGain,
  setRouteMuted,
  updateConfiguration
} from "../src/index.js";

describe("configuration state", () => {
  it("switches the active configuration in one state transition", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const next = activateConfiguration(state, "stream", "2026-07-03T10:05:00.000Z");

    expect(state.activeConfigurationId).toBe("studio");
    expect(next.activeConfigurationId).toBe("stream");
    expect(next.appliedAt).toBe("2026-07-03T10:05:00.000Z");
    expect(getActiveConfiguration(next).name).toBe("Stream");
  });

  it("rejects unknown configuration switches", () => {
    const state = createDefaultState();

    expect(() => activateConfiguration(state, "missing", "2026-07-03T10:00:00.000Z")).toThrow(
      "Unknown Loopwire configuration: missing"
    );
  });

  it("hides monitors without deleting them", () => {
    const state = createDefaultState();
    const hidden = setMonitorHidden(state, "studio", "headphones", true);
    const active = getActiveConfiguration(hidden);

    expect(active.monitors.map((monitor) => monitor.id)).toContain("headphones");
    expect(getVisibleMonitors(hidden, active).map((monitor) => monitor.id)).not.toContain("headphones");
    expect(hidden.hiddenMonitorIds).toEqual(["studio:headphones"]);

    const visible = setMonitorHidden(hidden, "studio", "headphones", false);
    expect(getVisibleMonitors(visible, active).map((monitor) => monitor.id)).toContain("headphones");
  });

  it("scopes monitor visibility to the configuration", () => {
    const state = createDefaultState();
    const hidden = setMonitorHidden(state, "studio", "headphones", true);
    const studio = getConfigurationById(hidden, "studio");
    const call = getConfigurationById(hidden, "call");

    expect(isMonitorHidden(hidden, studio, "headphones")).toBe(true);
    expect(isMonitorHidden(hidden, call, "headphones")).toBe(false);
    expect(getVisibleMonitors(hidden, call).map((monitor) => monitor.id)).toContain("headphones");
  });

  it("honors legacy bare hidden monitor ids while writing scoped ids", () => {
    const state = { ...createDefaultState(), hiddenMonitorIds: ["headphones"] };
    const studio = getConfigurationById(state, "studio");

    expect(isMonitorHidden(state, studio, "headphones")).toBe(true);

    const visible = setMonitorHidden(state, "studio", "headphones", false);
    expect(visible.hiddenMonitorIds).toEqual([]);
  });

  it("accepts physical device names on monitor endpoints", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = updateConfiguration(
      state,
      "studio",
      {
        monitors: [{ id: "headphones", label: "Headphones", role: "monitor", channels: 2, deviceName: "alsa_output.usb" }]
      },
      "2026-07-03T10:08:00.000Z"
    );

    expect(result.configuration.monitors[0]?.deviceName).toBe("alsa_output.usb");
  });

  it("creates a named configuration without changing the active configuration", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = createConfiguration(
      state,
      {
        name: "Podcast Mix",
        description: "Guest, browser, and recorder routing."
      },
      "2026-07-03T10:10:00.000Z"
    );

    expect(result.configuration.id).toBe("podcast-mix");
    expect(result.configuration.outputs).toHaveLength(1);
    expect(result.state.configurations).toHaveLength(4);
    expect(result.state.activeConfigurationId).toBe("studio");
  });

  it("updates a configuration without mutating the original state", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = updateConfiguration(
      state,
      "studio",
      { name: "Studio A", description: "Primary recording setup." },
      "2026-07-03T10:20:00.000Z"
    );

    expect(getActiveConfiguration(state).name).toBe("Studio");
    expect(getActiveConfiguration(result.state).name).toBe("Studio A");
    expect(result.configuration.updatedAt).toBe("2026-07-03T10:20:00.000Z");
  });

  it("sets and clears host device names on endpoints", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const sourceBound = setEndpointDeviceName(state, "studio", "mic", "  alsa_input.usb_mic:capture_FL  ", "2026-07-03T10:21:00.000Z");
    const outputBound = setEndpointDeviceName(
      sourceBound.state,
      "studio",
      "recorder",
      "pw:loopwire-recorder",
      "2026-07-03T10:22:00.000Z"
    );
    const monitorBound = setEndpointDeviceName(
      outputBound.state,
      "studio",
      "headphones",
      "alsa_output.usb_headphones",
      "2026-07-03T10:23:00.000Z"
    );
    const cleared = setEndpointDeviceName(monitorBound.state, "studio", "mic", "", "2026-07-03T10:24:00.000Z");

    expect(sourceBound.configuration.inputs.find((input) => input.id === "mic")?.deviceName).toBe(
      "alsa_input.usb_mic:capture_FL"
    );
    expect(outputBound.configuration.outputs.find((output) => output.id === "recorder")?.deviceName).toBe(
      "pw:loopwire-recorder"
    );
    expect(monitorBound.configuration.monitors.find((monitor) => monitor.id === "headphones")?.deviceName).toBe(
      "alsa_output.usb_headphones"
    );
    expect(cleared.configuration.inputs.find((input) => input.id === "mic")?.deviceName).toBeUndefined();
    expect(getConfigurationById(state, "studio").inputs.find((input) => input.id === "mic")?.deviceName).toBeUndefined();
  });

  it("rejects host binding for unknown endpoints", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");

    expect(() =>
      setEndpointDeviceName(state, "studio", "missing", "alsa_input.missing", "2026-07-03T10:21:00.000Z")
    ).toThrow("Unknown Loopwire endpoint: missing");
  });

  it("adds an input source and routes it to the first output", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = addInputSourceToConfiguration(
      state,
      "studio",
      { id: "meeting-app", label: "Meeting App", channels: 2 },
      "2026-07-03T10:25:00.000Z"
    );

    expect(getConfigurationById(state, "studio").inputs.map((input) => input.id)).not.toContain("meeting-app");
    expect(result.configuration.inputs.at(-1)).toMatchObject({
      id: "meeting-app",
      label: "Meeting App",
      role: "input",
      channels: 2
    });
    expect(result.configuration.routes.at(-1)).toMatchObject({
      id: "meeting-app-recorder",
      from: "meeting-app",
      to: "recorder",
      gain: 1,
      muted: false
    });
    expect(result.configuration.updatedAt).toBe("2026-07-03T10:25:00.000Z");
  });

  it("rejects adding a duplicate input source", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");

    expect(() =>
      addInputSourceToConfiguration(
        state,
        "studio",
        { id: "browser", label: "Browser", channels: 2 },
        "2026-07-03T10:25:00.000Z"
      )
    ).toThrow("Input source already exists in configuration: Browser");
  });

  it("adds an output bus and routes existing inputs to it", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = addOutputBusToConfiguration(
      state,
      "studio",
      { id: "broadcast", label: "Broadcast Bus", channels: 2 },
      "2026-07-03T10:27:00.000Z"
    );

    expect(getConfigurationById(state, "studio").outputs.map((output) => output.id)).not.toContain("broadcast");
    expect(result.configuration.outputs.at(-1)).toMatchObject({
      id: "broadcast",
      label: "Broadcast Bus",
      role: "output",
      channels: 2
    });
    expect(result.configuration.routes.slice(-2).map((route) => [route.id, route.from, route.to, route.gain])).toEqual([
      ["mic-broadcast", "mic", "broadcast", 1],
      ["browser-broadcast", "browser", "broadcast", 1]
    ]);
    expect(result.configuration.updatedAt).toBe("2026-07-03T10:27:00.000Z");
  });

  it("adds an output bus with a host device name for native link targets", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = addOutputBusToConfiguration(
      state,
      "studio",
      {
        id: "studio-headphones",
        label: "Studio Headphones",
        channels: 2,
        deviceName: "alsa_output.usb_studio_headphones.analog-stereo"
      },
      "2026-07-03T10:27:00.000Z"
    );

    expect(result.configuration.outputs.at(-1)).toMatchObject({
      id: "studio-headphones",
      label: "Studio Headphones",
      role: "output",
      channels: 2,
      deviceName: "alsa_output.usb_studio_headphones.analog-stereo"
    });
  });

  it("routes only host-backed inputs when adding a native host output", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const sourceResult = addInputSourceToConfiguration(
      state,
      "studio",
      {
        id: "system-audio",
        label: "System Audio",
        channels: 2,
        deviceName: "firefox"
      },
      "2026-07-03T10:26:00.000Z"
    );
    const outputResult = addOutputBusToConfiguration(
      sourceResult.state,
      "studio",
      {
        id: "studio-headphones",
        label: "Studio Headphones",
        channels: 2,
        deviceName: "alsa_output.usb_studio_headphones.analog-stereo",
        routeExistingInputs: "host-device"
      },
      "2026-07-03T10:27:00.000Z"
    );

    expect(outputResult.configuration.routes.map((route) => [route.from, route.to])).toContainEqual([
      "system-audio",
      "studio-headphones"
    ]);
    expect(outputResult.configuration.routes.map((route) => [route.from, route.to])).not.toContainEqual([
      "mic",
      "studio-headphones"
    ]);
    expect(outputResult.configuration.routes.map((route) => [route.from, route.to])).not.toContainEqual([
      "browser",
      "studio-headphones"
    ]);
  });

  it("rejects adding a duplicate output bus", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");

    expect(() =>
      addOutputBusToConfiguration(
        state,
        "studio",
        { id: "recorder", label: "Recorder Bus", channels: 2 },
        "2026-07-03T10:27:00.000Z"
      )
    ).toThrow("Output bus already exists in configuration: Recorder Bus");
  });

  it("adds a monitor endpoint without changing routes", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = addMonitorToConfiguration(
      state,
      "studio",
      { id: "producer", label: "Producer Monitor", channels: 2 },
      "2026-07-03T10:28:00.000Z"
    );

    expect(getConfigurationById(state, "studio").monitors.map((monitor) => monitor.id)).not.toContain("producer");
    expect(result.configuration.monitors.at(-1)).toMatchObject({
      id: "producer",
      label: "Producer Monitor",
      role: "monitor",
      channels: 2
    });
    expect(result.configuration.routes).toHaveLength(getConfigurationById(state, "studio").routes.length);
    expect(result.configuration.updatedAt).toBe("2026-07-03T10:28:00.000Z");
  });

  it("rejects adding a duplicate monitor", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");

    expect(() =>
      addMonitorToConfiguration(
        state,
        "studio",
        { id: "headphones", label: "Headphones", channels: 2 },
        "2026-07-03T10:28:00.000Z"
      )
    ).toThrow("Monitor already exists in configuration: Headphones");
  });

  it("removes an input source and its routes without mutating the original state", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = removeInputSourceFromConfiguration(state, "studio", "browser", "2026-07-03T10:29:00.000Z");

    expect(getConfigurationById(state, "studio").inputs.map((input) => input.id)).toContain("browser");
    expect(result.configuration.inputs.map((input) => input.id)).not.toContain("browser");
    expect(result.configuration.routes.map((route) => route.from)).not.toContain("browser");
    expect(result.configuration.updatedAt).toBe("2026-07-03T10:29:00.000Z");
  });

  it("removes an output bus and its routes while keeping another output", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const added = addOutputBusToConfiguration(
      state,
      "studio",
      { id: "broadcast", label: "Broadcast Bus", channels: 2 },
      "2026-07-03T10:27:00.000Z"
    );
    const result = removeOutputBusFromConfiguration(added.state, "studio", "broadcast", "2026-07-03T10:29:00.000Z");

    expect(result.configuration.outputs.map((output) => output.id)).toEqual(["recorder"]);
    expect(result.configuration.routes.map((route) => route.to)).not.toContain("broadcast");
    expect(result.configuration.routes.map((route) => route.to)).toEqual(["recorder", "recorder"]);
  });

  it("rejects removing the final output bus", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");

    expect(() => removeOutputBusFromConfiguration(state, "studio", "recorder", "2026-07-03T10:29:00.000Z")).toThrow(
      "Configuration must keep at least one output."
    );
  });

  it("removes a monitor endpoint and clears its hidden state", () => {
    const state = setMonitorHidden(createDefaultState("2026-07-03T10:00:00.000Z"), "studio", "headphones", true);
    const result = removeMonitorFromConfiguration(state, "studio", "headphones", "2026-07-03T10:29:00.000Z");

    expect(result.configuration.monitors.map((monitor) => monitor.id)).not.toContain("headphones");
    expect(result.state.hiddenMonitorIds).not.toContain("studio:headphones");
  });

  it("duplicates configurations with unique ids", () => {
    const state = createDefaultState();
    const first = duplicateConfiguration(state, "studio", "2026-07-03T10:30:00.000Z");
    const second = duplicateConfiguration(first.state, "studio", "2026-07-03T10:31:00.000Z");

    expect(first.configuration.id).toBe("studio-copy");
    expect(first.configuration.name).toBe("Studio Copy");
    expect(second.configuration.id).toBe("studio-copy-2");
    expect(second.state.configurations.map((configuration) => configuration.id)).toContain("studio-copy-2");
  });

  it("deletes the active configuration by selecting the next available configuration", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = deleteConfiguration(state, "studio", "2026-07-03T10:40:00.000Z");

    expect(result.removedConfiguration.name).toBe("Studio");
    expect(result.state.configurations.map((configuration) => configuration.id)).not.toContain("studio");
    expect(result.state.activeConfigurationId).toBe("call");
    expect(result.state.appliedAt).toBe("2026-07-03T10:40:00.000Z");
  });

  it("rejects deleting the final configuration", () => {
    const state = createDefaultState();
    const only = { ...state, configurations: [state.configurations[0]!], activeConfigurationId: "studio" };

    expect(() => deleteConfiguration(only, "studio", "2026-07-03T10:40:00.000Z")).toThrow(
      "Loopwire must keep at least one configuration."
    );
  });

  it("updates route gain without mutating the original configuration", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = setRouteGain(state, "studio", "mic-recorder", 0.5, "2026-07-03T10:50:00.000Z");
    const originalRoute = getConfigurationById(state, "studio").routes.find((route) => route.id === "mic-recorder");
    const updatedRoute = result.configuration.routes.find((route) => route.id === "mic-recorder");

    expect(originalRoute?.gain).toBe(0.86);
    expect(updatedRoute?.gain).toBe(0.5);
    expect(result.configuration.updatedAt).toBe("2026-07-03T10:50:00.000Z");
  });

  it("toggles route mute state", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const muted = setRouteMuted(state, "studio", "browser-recorder", true, "2026-07-03T10:55:00.000Z");
    const route = muted.configuration.routes.find((candidate) => candidate.id === "browser-recorder");

    expect(route?.muted).toBe(true);
  });

  it("keeps independent route controls when one source targets multiple outputs", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = updateConfiguration(
      state,
      "studio",
      {
        outputs: [
          { id: "recorder", label: "Recorder Bus", role: "output", channels: 2 },
          { id: "broadcast", label: "Broadcast Bus", role: "output", channels: 2 }
        ],
        routes: [
          { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.86, muted: false },
          { id: "mic-broadcast", from: "mic", to: "broadcast", gain: 0.42, muted: true }
        ]
      },
      "2026-07-03T10:57:00.000Z"
    );

    expect(result.configuration.routes.map((route) => [route.id, route.gain, route.muted])).toEqual([
      ["mic-recorder", 0.86, false],
      ["mic-broadcast", 0.42, true]
    ]);
  });

  it("adds an explicit route between an existing source and output", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const addedOutput = addOutputBusToConfiguration(
      state,
      "studio",
      { id: "broadcast", label: "Broadcast Bus", channels: 2, routeExistingInputs: false },
      "2026-07-03T10:58:00.000Z"
    );
    const result = addRouteToConfiguration(
      addedOutput.state,
      "studio",
      { from: "mic", to: "broadcast", gain: 0.72 },
      "2026-07-03T10:59:00.000Z"
    );

    expect(result.configuration.routes.at(-1)).toMatchObject({
      id: "mic-broadcast",
      from: "mic",
      to: "broadcast",
      gain: 0.72,
      muted: false
    });
    expect(result.configuration.updatedAt).toBe("2026-07-03T10:59:00.000Z");
  });

  it("rejects duplicate route pairs", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");

    expect(() =>
      addRouteToConfiguration(
        state,
        "studio",
        { id: "another-mic-recorder", from: "mic", to: "recorder" },
        "2026-07-03T10:59:00.000Z"
      )
    ).toThrow("Route already exists: Studio Mic to Recorder Bus");
  });

  it("removes a route without deleting its endpoints", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");
    const result = removeRouteFromConfiguration(state, "studio", "browser-recorder", "2026-07-03T10:59:00.000Z");

    expect(result.configuration.routes.map((route) => route.id)).not.toContain("browser-recorder");
    expect(result.configuration.inputs.map((input) => input.id)).toContain("browser");
    expect(result.configuration.outputs.map((output) => output.id)).toContain("recorder");
  });

  it("rejects duplicate route pairs during graph validation", () => {
    const state = createDefaultState("2026-07-03T10:00:00.000Z");

    expect(() =>
      updateConfiguration(
        state,
        "studio",
        {
          routes: [
            { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.86, muted: false },
            { id: "mic-recorder-copy", from: "mic", to: "recorder", gain: 0.4, muted: true }
          ]
        },
        "2026-07-03T10:59:00.000Z"
      )
    ).toThrow("Duplicate route pair in configuration: mic to recorder");
  });

  it("rejects route gain outside the supported range", () => {
    const state = createDefaultState();

    expect(() => setRouteGain(state, "studio", "mic-recorder", 1.25, "2026-07-03T10:56:00.000Z")).toThrow(
      "Route gain must be between 0 and 1."
    );
  });
});
