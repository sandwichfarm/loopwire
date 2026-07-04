import { describe, expect, it } from "vitest";
import {
  createJackGraphRuntimeAdapter,
  createJackVirtualPortCommandProvider,
  describeJackPortReadiness,
  describeJackPortRequirements,
  type HostRuntimeConfiguration,
  type JackVirtualPortProvisionPlan
} from "../src/index.js";
import type { CommandResult, CommandRunner } from "../src/types.js";

type CommandKey = string;
type CommandFixture = Partial<CommandResult> | readonly Partial<CommandResult>[];

const jackConfiguration: HostRuntimeConfiguration = {
  id: "JACK Mix",
  name: "JACK Mix",
  inputs: [{ id: "mic", label: "Studio Mic", channels: 2, deviceName: "studio_mic" }],
  outputs: [{ id: "program", label: "Program Out", channels: 2, deviceName: "loopwire_program" }],
  routes: [{ id: "mic-program", from: "mic", to: "program", muted: false }]
};

const monitoredJackConfiguration: HostRuntimeConfiguration = {
  ...jackConfiguration,
  monitors: [{ id: "headphones", label: "Headphones", channels: 2, deviceName: "system" }]
};

function createRecordingRunner(results: Record<CommandKey, CommandFixture>): {
  readonly runner: CommandRunner;
  readonly calls: string[];
} {
  const calls: string[] = [];
  const queues = new Map(
    Object.entries(results).map(([key, value]) => [key, Array.isArray(value) ? [...value] : [value]])
  );

  return {
    calls,
    runner: {
      async run(command, args) {
        const key = [command, ...args].join(" ");
        calls.push(key);
        const result = shiftFixture(queues, key) ?? shiftFixture(queues, command) ?? {};

        return {
          command,
          args,
          exitCode: result.exitCode ?? 0,
          stdout: result.stdout ?? "",
          stderr: result.stderr ?? "",
          ...(result.errorCode ? { errorCode: result.errorCode } : {})
        };
      }
    }
  };
}

function shiftFixture(queues: Map<string, Partial<CommandResult>[]>, key: string): Partial<CommandResult> | undefined {
  const queue = queues.get(key);

  if (!queue || queue.length === 0) {
    return undefined;
  }

  return queue.length === 1 ? queue[0] : queue.shift();
}

describe("createJackGraphRuntimeAdapter", () => {
  it("dry-runs apply and verify without mutating the host", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createJackGraphRuntimeAdapter(runner);

    const apply = await adapter.apply(jackConfiguration);
    const verify = await adapter.verify(jackConfiguration);

    expect(apply).toEqual({ ok: true, message: "Dry run planned 1 JACK connection plan(s)" });
    expect(verify).toEqual({ ok: true, message: "Dry run verified 1 JACK connection plan(s)" });
    expect(calls).toEqual([]);
    expect(adapter.commandLog.map((entry) => [entry.operation, entry.command, entry.args.join(" "), entry.skipped])).toEqual([
      ["apply", "jack_lsp", "", true],
      ["apply", "jack_lsp", "-c", true],
      ["verify", "jack_lsp", "", true],
      ["verify", "jack_lsp", "-c", true]
    ]);
  });

  it("connects matching JACK ports by endpoint device names", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: "" },
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(jackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 2 JACK port pair(s); 0 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("skips JACK connections that already exist", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: jackConnections([["studio_mic:capture_1", "loopwire_program:playback_1"]]) },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(jackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 1 JACK port pair(s); 1 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("disconnects muted JACK route connections during apply", async () => {
    const mutedConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", muted: true }]
    };
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": {
        stdout: jackConnections([
          ["studio_mic:capture_1", "loopwire_program:playback_1"],
          ["studio_mic:capture_2", "loopwire_program:playback_2"]
        ])
      },
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(mutedConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Disconnected 2 muted JACK port pair(s); Connected 0 JACK port pair(s); 0 already connected"
    });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("connects configured outputs to physical JACK monitor sinks", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPortsWithMonitor() },
      "jack_lsp -c": { stdout: "" },
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" },
      "jack_connect loopwire_program:monitor_1 system:playback_1": { stdout: "" },
      "jack_connect loopwire_program:monitor_2 system:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(monitoredJackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 4 JACK port pair(s); 0 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2",
      "jack_connect loopwire_program:monitor_1 system:playback_1",
      "jack_connect loopwire_program:monitor_2 system:playback_2"
    ]);
  });

  it("connects Loopwire-owned JACK route ports when app endpoints have no host device names", async () => {
    const virtualJackConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      inputs: [{ id: "mic", label: "Studio Mic", channels: 2 }],
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: virtualLoopwirePorts() },
      "jack_lsp -c": { stdout: "" },
      "jack_connect loopwire_jack_mix_input_mic:capture_1 loopwire_jack_mix_program:playback_1": { stdout: "" },
      "jack_connect loopwire_jack_mix_input_mic:capture_2 loopwire_jack_mix_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(virtualJackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 2 JACK port pair(s); 0 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect loopwire_jack_mix_input_mic:capture_1 loopwire_jack_mix_program:playback_1",
      "jack_connect loopwire_jack_mix_input_mic:capture_2 loopwire_jack_mix_program:playback_2"
    ]);
  });

  it("asks an injected provider to create missing Loopwire-owned JACK route ports before connecting", async () => {
    const virtualJackConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      inputs: [{ id: "mic", label: "Studio Mic", channels: 2 }],
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };
    const providerPlans: JackVirtualPortProvisionPlan[] = [];
    const { runner, calls } = createRecordingRunner({
      jack_lsp: [{ stdout: "" }, { stdout: virtualLoopwirePorts() }],
      "jack_lsp -c": { stdout: "" },
      "jack_connect loopwire_jack_mix_input_mic:capture_1 loopwire_jack_mix_program:playback_1": { stdout: "" },
      "jack_connect loopwire_jack_mix_input_mic:capture_2 loopwire_jack_mix_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, {
      mode: "apply",
      virtualPortProvider: {
        ensurePorts(plan) {
          providerPlans.push(plan);
          return { ok: true, message: "created test JACK ports" };
        }
      }
    });

    const result = await adapter.apply(virtualJackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 2 JACK port pair(s); 0 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_lsp",
      "jack_connect loopwire_jack_mix_input_mic:capture_1 loopwire_jack_mix_program:playback_1",
      "jack_connect loopwire_jack_mix_input_mic:capture_2 loopwire_jack_mix_program:playback_2"
    ]);
    expect(providerPlans).toHaveLength(1);
    expect(providerPlans[0]).toMatchObject({
      configurationId: "JACK Mix",
      missingPorts: [
        "loopwire_jack_mix_input_mic:capture_1",
        "loopwire_jack_mix_input_mic:capture_2",
        "loopwire_jack_mix_program:playback_1",
        "loopwire_jack_mix_program:playback_2"
      ]
    });
    expect(providerPlans[0]?.requirements.map((requirement) => requirement.source)).toEqual([
      "loopwire-owned",
      "loopwire-owned"
    ]);
  });

  it("fails closed when the injected provider does not create required JACK ports", async () => {
    const virtualJackConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      inputs: [{ id: "mic", label: "Studio Mic", channels: 2 }],
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      jack_lsp: [{ stdout: "" }, { stdout: "" }],
      "jack_lsp -c": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, {
      mode: "apply",
      virtualPortProvider: {
        ensurePorts() {
          return { ok: true, message: "claimed success" };
        }
      }
    });

    const result = await adapter.apply(virtualJackConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "Loopwire JACK virtual port provider did not create required ports: " +
        "loopwire_jack_mix_input_mic:capture_1, loopwire_jack_mix_input_mic:capture_2, " +
        "loopwire_jack_mix_program:playback_1, loopwire_jack_mix_program:playback_2"
    });
    expect(calls).toEqual(["jack_lsp", "jack_lsp -c", "jack_lsp"]);
  });

  it("connects Loopwire-owned JACK monitor ports when app monitors have no host device names", async () => {
    const virtualMonitorConfiguration: HostRuntimeConfiguration = {
      ...monitoredJackConfiguration,
      monitors: [{ id: "headphones", label: "Headphones", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: `${jackPortsWithMonitor()}\n${virtualMonitorTargetPorts()}` },
      "jack_lsp -c": { stdout: "" },
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" },
      "jack_connect loopwire_program:monitor_1 loopwire_jack_mix_monitor_headphones:playback_1": { stdout: "" },
      "jack_connect loopwire_program:monitor_2 loopwire_jack_mix_monitor_headphones:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(virtualMonitorConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 4 JACK port pair(s); 0 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2",
      "jack_connect loopwire_program:monitor_1 loopwire_jack_mix_monitor_headphones:playback_1",
      "jack_connect loopwire_program:monitor_2 loopwire_jack_mix_monitor_headphones:playback_2"
    ]);
  });

  it("fails verification when a configured JACK connection is missing", async () => {
    const { runner } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: jackConnections([["studio_mic:capture_1", "loopwire_program:playback_1"]]) }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(jackConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Missing JACK connection(s): studio_mic:capture_2 -> loopwire_program:playback_2"
    });
  });

  it("fails verification when a muted JACK route is still connected", async () => {
    const mutedConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", muted: true }]
    };
    const { runner } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": {
        stdout: jackConnections([
          ["studio_mic:capture_1", "loopwire_program:playback_1"],
          ["studio_mic:capture_2", "loopwire_program:playback_2"]
        ])
      }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(mutedConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "Muted JACK connection(s) still connected: studio_mic:capture_1 -> loopwire_program:playback_1, " +
        "studio_mic:capture_2 -> loopwire_program:playback_2"
    });
  });

  it("disconnects only JACK connections that match the configuration", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": {
        stdout: jackConnections([
          ["studio_mic:capture_1", "loopwire_program:playback_1"],
          ["studio_mic:capture_2", "loopwire_program:playback_2"],
          ["other:output_1", "loopwire_program:playback_1"]
        ])
      },
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.rollback(jackConfiguration);

    expect(result).toEqual({ ok: true, message: "Disconnected 2 JACK port pair(s)" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("rolls back JACK connections created before a later connection fails", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: "" },
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { exitCode: 1, stderr: "connect failed\n" },
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(jackConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Could not connect JACK ports studio_mic:capture_2 -> loopwire_program:playback_2: connect failed"
    });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2",
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1"
    ]);
  });

  it("rejects non-unity gain before attempting JACK commands", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...jackConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", gain: 0.5, muted: false }]
    });

    expect(result).toEqual({
      ok: false,
      message: "Route mic-program has gain 0.5; native JACK connections only support unity gain for now"
    });
    expect(calls).toEqual([]);
  });

  it("reports missing Loopwire-owned JACK route input ports without connecting", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...jackConfiguration,
      inputs: [{ id: "mic", label: "Studio Mic", channels: 2 }]
    });

    expect(result).toEqual({
      ok: false,
      message:
        "Missing JACK output ports for Studio Mic (loopwire_jack_mix_input_mic): " +
        "loopwire_jack_mix_input_mic:capture_1, loopwire_jack_mix_input_mic:capture_2"
    });
    expect(calls).toEqual(["jack_lsp", "jack_lsp -c"]);
  });

  it("reports missing Loopwire-owned JACK route output ports without connecting", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: ["studio_mic:capture_1", "studio_mic:capture_2"].join("\n") }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...jackConfiguration,
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    });

    expect(result).toEqual({
      ok: false,
      message:
        "Missing JACK input ports for Program Out (loopwire_jack_mix_program): " +
        "loopwire_jack_mix_program:playback_1, loopwire_jack_mix_program:playback_2"
    });
    expect(calls).toEqual(["jack_lsp", "jack_lsp -c"]);
  });

  it("reports missing Loopwire-owned JACK monitor source ports without connecting", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...monitoredJackConfiguration,
      outputs: [{ id: "program", label: "Program Out", channels: 2 }],
      routes: []
    });

    expect(result).toEqual({
      ok: false,
      message:
        "Missing JACK monitor output ports for Program Out (loopwire_jack_mix_program): " +
        "loopwire_jack_mix_program:monitor_1, loopwire_jack_mix_program:monitor_2"
    });
    expect(calls).toEqual(["jack_lsp", "jack_lsp -c"]);
  });

  it("reports missing Loopwire-owned JACK monitor target ports without connecting", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: ["loopwire_program:monitor_1", "loopwire_program:monitor_2"].join("\n") }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...jackConfiguration,
      routes: [],
      monitors: [{ id: "headphones", label: "Headphones", channels: 2 }]
    });

    expect(result).toEqual({
      ok: false,
      message:
        "Missing JACK input ports for Headphones (loopwire_jack_mix_monitor_headphones): " +
        "loopwire_jack_mix_monitor_headphones:playback_1, loopwire_jack_mix_monitor_headphones:playback_2"
    });
    expect(calls).toEqual(["jack_lsp", "jack_lsp -c"]);
  });
});

describe("describeJackPortRequirements", () => {
  it("describes deterministic Loopwire-owned route port requirements", () => {
    const virtualJackConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      inputs: [{ id: "mic", label: "Studio Mic", channels: 2 }],
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };

    expect(describeJackPortRequirements(virtualJackConfiguration)).toEqual([
      {
        endpointId: "mic",
        endpointLabel: "Studio Mic",
        kind: "route-source",
        deviceName: "loopwire_jack_mix_input_mic",
        source: "loopwire-owned",
        channelCount: 2,
        suggestedPorts: ["loopwire_jack_mix_input_mic:capture_1", "loopwire_jack_mix_input_mic:capture_2"]
      },
      {
        endpointId: "program",
        endpointLabel: "Program Out",
        kind: "route-target",
        deviceName: "loopwire_jack_mix_program",
        source: "loopwire-owned",
        channelCount: 2,
        suggestedPorts: ["loopwire_jack_mix_program:playback_1", "loopwire_jack_mix_program:playback_2"]
      }
    ]);
  });

  it("describes configured and Loopwire-owned monitor requirements", () => {
    expect(describeJackPortRequirements(monitoredJackConfiguration)).toEqual([
      {
        endpointId: "mic",
        endpointLabel: "Studio Mic",
        kind: "route-source",
        deviceName: "studio_mic",
        source: "configured",
        channelCount: 2,
        suggestedPorts: ["studio_mic:capture_1", "studio_mic:capture_2"]
      },
      {
        endpointId: "program",
        endpointLabel: "Program Out",
        kind: "route-target",
        deviceName: "loopwire_program",
        source: "configured",
        channelCount: 2,
        suggestedPorts: ["loopwire_program:playback_1", "loopwire_program:playback_2"]
      },
      {
        endpointId: "program",
        endpointLabel: "Program Out",
        kind: "monitor-source",
        deviceName: "loopwire_program",
        source: "configured",
        channelCount: 2,
        suggestedPorts: ["loopwire_program:monitor_1", "loopwire_program:monitor_2"]
      },
      {
        endpointId: "headphones",
        endpointLabel: "Headphones",
        kind: "monitor-target",
        deviceName: "system",
        source: "configured",
        channelCount: 2,
        suggestedPorts: ["system:playback_1", "system:playback_2"]
      }
    ]);
  });
});

describe("describeJackPortReadiness", () => {
  it("reports matched and missing JACK ports with the same names used by runtime plans", () => {
    const virtualJackConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      inputs: [{ id: "mic", label: "Studio Mic", channels: 2 }],
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };

    expect(
      describeJackPortReadiness(virtualJackConfiguration, [
        "loopwire_jack_mix_input_mic:capture_1",
        "loopwire_jack_mix_program:playback_1",
        "loopwire_jack_mix_program:playback_2"
      ])
    ).toEqual({
      ok: false,
      portCount: 3,
      missingCount: 1,
      requirements: [
        {
          endpointId: "mic",
          endpointLabel: "Studio Mic",
          kind: "route-source",
          deviceName: "loopwire_jack_mix_input_mic",
          source: "loopwire-owned",
          channelCount: 2,
          suggestedPorts: ["loopwire_jack_mix_input_mic:capture_1", "loopwire_jack_mix_input_mic:capture_2"],
          ready: false,
          matchedPorts: ["loopwire_jack_mix_input_mic:capture_1"],
          missingPorts: ["loopwire_jack_mix_input_mic:capture_2"]
        },
        {
          endpointId: "program",
          endpointLabel: "Program Out",
          kind: "route-target",
          deviceName: "loopwire_jack_mix_program",
          source: "loopwire-owned",
          channelCount: 2,
          suggestedPorts: ["loopwire_jack_mix_program:playback_1", "loopwire_jack_mix_program:playback_2"],
          ready: true,
          matchedPorts: ["loopwire_jack_mix_program:playback_1", "loopwire_jack_mix_program:playback_2"],
          missingPorts: []
        }
      ]
    });
  });
});

describe("createJackVirtualPortCommandProvider", () => {
  const plan: JackVirtualPortProvisionPlan = {
    configurationId: "JACK Mix",
    missingPorts: [
      "loopwire_jack_mix_input_mic:capture_1",
      "loopwire_jack_mix_program:playback_1"
    ],
    requirements: [
      {
        endpointId: "mic",
        endpointLabel: "Studio Mic",
        kind: "route-source",
        deviceName: "loopwire_jack_mix_input_mic",
        source: "loopwire-owned",
        channelCount: 1,
        suggestedPorts: ["loopwire_jack_mix_input_mic:capture_1"],
        ready: false,
        matchedPorts: [],
        missingPorts: ["loopwire_jack_mix_input_mic:capture_1"]
      },
      {
        endpointId: "program",
        endpointLabel: "Program Out",
        kind: "route-target",
        deviceName: "loopwire_jack_mix_program",
        source: "loopwire-owned",
        channelCount: 1,
        suggestedPorts: ["loopwire_jack_mix_program:playback_1"],
        ready: false,
        matchedPorts: [],
        missingPorts: ["loopwire_jack_mix_program:playback_1"]
      }
    ]
  };

  it("passes the provision plan to a command runner as stable arguments", async () => {
    const command = providerCommand();
    const { runner, calls } = createRecordingRunner({
      [command]: {
        stdout: "created ports\n"
      }
    });
    const provider = createJackVirtualPortCommandProvider(runner);

    await expect(provider.ensurePorts(plan)).resolves.toEqual({
      ok: true,
      message: "created ports"
    });
    expect(calls).toEqual([command]);
  });

  it("reports command provider failures without hiding stderr", async () => {
    const command = providerCommand("custom-provider");
    const { runner } = createRecordingRunner({
      [command]: {
        exitCode: 2,
        stderr: "jack server refused client\n"
      }
    });
    const provider = createJackVirtualPortCommandProvider(runner, { command: "custom-provider" });

    await expect(provider.ensurePorts(plan)).resolves.toEqual({
      ok: false,
      message: "JACK virtual port provider failed: jack server refused client"
    });
  });
});

function providerCommand(command = "loopwire-jack-ports"): string {
  return [
    command,
    "ensure",
    "--configuration-id",
    "JACK Mix",
    "--requirement",
    "route-source:loopwire-owned:mic:loopwire_jack_mix_input_mic:1",
    "--requirement",
    "route-target:loopwire-owned:program:loopwire_jack_mix_program:1",
    "--port",
    "loopwire_jack_mix_input_mic:capture_1",
    "--port",
    "loopwire_jack_mix_program:playback_1"
  ].join(" ");
}

function jackPorts(): string {
  return [
    "studio_mic:capture_1",
    "studio_mic:capture_2",
    "loopwire_program:playback_1",
    "loopwire_program:playback_2",
    "other:output_1"
  ].join("\n");
}

function jackPortsWithMonitor(): string {
  return `${jackPorts()}\nloopwire_program:monitor_1\nloopwire_program:monitor_2\nsystem:playback_1\nsystem:playback_2`;
}

function virtualLoopwirePorts(): string {
  return [
    "loopwire_jack_mix_input_mic:capture_1",
    "loopwire_jack_mix_input_mic:capture_2",
    "loopwire_jack_mix_program:playback_1",
    "loopwire_jack_mix_program:playback_2"
  ].join("\n");
}

function virtualMonitorTargetPorts(): string {
  return [
    "loopwire_jack_mix_monitor_headphones:playback_1",
    "loopwire_jack_mix_monitor_headphones:playback_2"
  ].join("\n");
}

function jackConnections(pairs: readonly (readonly [string, string])[]): string {
  return pairs.map(([source, target]) => `${source}\n   ${target}`).join("\n");
}
