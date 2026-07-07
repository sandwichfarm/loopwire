<script lang="ts">
  import { tick } from "svelte";
  import type { AudioEndpoint, LoopwireConfiguration } from "@loopwire/core";
  import { isEndpointEnabled } from "@loopwire/core";
  import { deviceStore, hostCatalog, levelStore, reapplySelectedDevice, uiStore } from "../app";
  import type { SourceCatalogEntry } from "../services/hostCatalog";
  import {
    cablePath,
    channelCablesFor,
    dragConnection,
    type DragEndpointInfo,
    type DragPortRole,
    type Point
  } from "../cables/geometry";
  import type { IconName } from "./Icon.svelte";
  import type { MenuSection } from "./PopupMenu.svelte";
  import type { RenderedCable } from "./CableLayer.svelte";
  import BusBlock from "./BusBlock.svelte";
  import CableLayer from "./CableLayer.svelte";
  import ColumnHeader from "./ColumnHeader.svelte";
  import DeviceTitle from "./DeviceTitle.svelte";
  import MonitorCard from "./MonitorCard.svelte";
  import PopupMenu from "./PopupMenu.svelte";
  import SourceCard from "./SourceCard.svelte";

  interface Props {
    readonly device: LoopwireConfiguration;
  }

  const { device }: Props = $props();

  const { canvasSelection, expandedOptions, monitorsHiddenDevices, renameEditing } = uiStore;
  const { sources: catalogSources, monitors: catalogMonitors } = hostCatalog;

  let graphElement: HTMLDivElement | undefined = $state();
  let anchors: ReadonlyMap<string, Point> = $state(new Map());
  let openMenu: { readonly kind: "sources" | "buses" | "monitors"; readonly anchor: HTMLElement } | null = $state(null);
  let drag: {
    readonly from: DragEndpointInfo;
    readonly fromPortKey: string;
    point: Point;
  } | null = $state(null);

  const monitorsHidden = $derived($monitorsHiddenDevices.has(device.id));

  const sortedSources = $derived(
    [...device.inputs].sort((left, right) => {
      const leftPass = left.id === "pass-thru" ? 1 : 0;
      const rightPass = right.id === "pass-thru" ? 1 : 0;
      return leftPass - rightPass || left.label.localeCompare(right.label);
    })
  );

  const busStartChannels = $derived.by(() => {
    const map = new Map<string, number>();
    let start = 1;
    for (const bus of device.outputs) {
      map.set(bus.id, start);
      start += bus.channels;
    }
    return map;
  });

  const totalBusChannels = $derived(device.outputs.reduce((sum, bus) => sum + bus.channels, 0));

  const sourceSummary = $derived.by(() => {
    const named = device.inputs.filter((input) => input.id !== "pass-thru").length;
    const hasPassThru = device.inputs.some((input) => input.id === "pass-thru");
    const parts: string[] = [];

    if (named > 0) {
      parts.push(`${named} ${named === 1 ? "Source" : "Sources"}`);
    }

    if (hasPassThru) {
      parts.push("Pass-Thru");
    }

    return parts.join(", ") || "No sources";
  });

  const monitorSummary = $derived(
    device.monitors.length === 0 ? "No devices" : `${device.monitors.length} ${device.monitors.length === 1 ? "Device" : "Devices"}`
  );

  const channelCables = $derived(channelCablesFor(device));

  const endpointById = $derived(
    new Map([...device.inputs, ...device.outputs, ...device.monitors].map((endpoint) => [endpoint.id, endpoint]))
  );

  const renderedCables = $derived.by((): readonly RenderedCable[] => {
    const selection = $canvasSelection;
    return channelCables.flatMap((cable) => {
      const from = anchors.get(cable.fromPort);
      const to = anchors.get(cable.toPort);

      if (!from || !to) {
        return [];
      }

      const fromEndpoint = endpointById.get(cable.fromEndpointId);
      const toEndpoint = endpointById.get(cable.toEndpointId);
      const dimmed =
        (fromEndpoint && !isEndpointEnabled(fromEndpoint)) || (toEndpoint && !isEndpointEnabled(toEndpoint));
      const selected = selection?.kind === "route" && selection.routeId === cable.routeId;

      return [
        {
          id: cable.id,
          routeId: cable.routeId,
          path: cablePath(from, to),
          state: selected ? ("selected" as const) : dimmed ? ("dimmed" as const) : ("live" as const)
        }
      ];
    });
  });

  const draftPath = $derived.by(() => {
    if (!drag) {
      return null;
    }

    const from = anchors.get(drag.fromPortKey);
    return from ? cablePath(from, drag.point) : null;
  });

  function measureAnchors(): void {
    if (!graphElement) {
      return;
    }

    const base = graphElement.getBoundingClientRect();
    const next = new Map<string, Point>();

    for (const element of graphElement.querySelectorAll<HTMLElement>("[data-port]")) {
      const key = element.dataset.port;

      if (!key) {
        continue;
      }

      const rect = element.getBoundingClientRect();
      next.set(key, { x: rect.left + rect.width / 2 - base.left, y: rect.top + rect.height / 2 - base.top });
    }

    anchors = next;
  }

  $effect(() => {
    // re-measure whenever the rendered graph shape changes
    void device;
    void $expandedOptions;
    void monitorsHidden;
    void tick().then(measureAnchors);
  });

  $effect(() => {
    if (!graphElement) {
      return;
    }

    const observer = new ResizeObserver(() => measureAnchors());
    observer.observe(graphElement);
    return () => observer.disconnect();
  });

  $effect(() => {
    const endpointIds = new Set(endpointById.keys());
    const routeIds = new Set(device.routes.map((route) => route.id));
    uiStore.pruneSelection(endpointIds, routeIds);
  });

  function sourceIcon(endpoint: AudioEndpoint): IconName {
    if (endpoint.kind) {
      return endpoint.kind === "pass-thru" ? "loop" : endpoint.kind === "capture" ? "mic" : "app";
    }

    // Legacy states without kind metadata fall back to id/label heuristics.
    if (endpoint.id === "pass-thru") {
      return "loop";
    }

    if (/mic/i.test(endpoint.label) || /mic|capture/i.test(endpoint.deviceName ?? "")) {
      return "mic";
    }

    return "app";
  }

  function isAppSource(endpoint: AudioEndpoint): boolean {
    if (endpoint.kind) {
      return endpoint.kind === "app";
    }

    // Legacy states without kind metadata fall back to the pass-thru id heuristic.
    return endpoint.id !== "pass-thru";
  }

  function menuSourceIcon(candidate: SourceCatalogEntry): IconName {
    if (candidate.kind) {
      return candidate.kind === "capture" ? "mic" : "app";
    }

    // Unclassified candidates fall back to the category-name heuristic.
    return /mic|capture/i.test(candidate.category) ? "mic" : "app";
  }

  function reportIfFailed(result: { readonly ok: boolean; readonly message?: string }): void {
    if (!result.ok && result.message) {
      uiStore.pushToast("error", result.message);
    }
  }

  /** Manual host binding is a structural edit: the host graph must track the new port name. */
  function setHostBinding(endpointId: string, deviceName: string): void {
    const result = deviceStore.setHostBinding(device.id, endpointId, deviceName);
    reportIfFailed(result);

    if (result.ok) {
      reapplySelectedDevice();
    }
  }

  const sourceMenuSections = $derived.by((): readonly MenuSection[] => {
    const existingIds = new Set(device.inputs.map((input) => input.id));
    const existingLabels = new Set(device.inputs.map((input) => input.label.toLowerCase()));
    const available = $catalogSources.filter(
      (candidate) => !existingIds.has(candidate.id) && !existingLabels.has(candidate.label.toLowerCase())
    );
    const categories = [...new Set(available.map((candidate) => candidate.category))];

    return categories.map((category) => ({
      title: category,
      items: available
        .filter((candidate) => candidate.category === category)
        .map((candidate) => ({
          id: candidate.id,
          label: candidate.label,
          detail: candidate.detail,
          icon: menuSourceIcon(candidate)
        }))
    }));
  });

  const monitorMenuSections = $derived.by((): readonly MenuSection[] => {
    const existingIds = new Set(device.monitors.map((monitor) => monitor.id));
    const existingLabels = new Set(device.monitors.map((monitor) => monitor.label.toLowerCase()));
    const existingDevices = new Set(device.monitors.map((monitor) => monitor.deviceName).filter(Boolean));

    return [
      {
        title: "Playback Devices",
        items: $catalogMonitors
          .filter(
            (candidate) =>
              !existingIds.has(candidate.id) &&
              !existingLabels.has(candidate.label.toLowerCase()) &&
              (!candidate.deviceName || !existingDevices.has(candidate.deviceName))
          )
          .map((candidate) => ({
            id: candidate.id,
            label: candidate.label,
            detail: candidate.detail,
            icon: "speaker" as IconName
          }))
      }
    ];
  });

  function pickSource(candidateId: string): void {
    const candidate = $catalogSources.find((entry) => entry.id === candidateId);
    openMenu = null;

    if (!candidate) {
      return;
    }

    const result = deviceStore.addSource(device.id, candidate);
    reportIfFailed(result);

    if (result.ok) {
      const added = deviceStore.snapshot().configurations.find((configuration) => configuration.id === device.id);
      const endpoint = added?.inputs.find((input) => input.label === candidate.label);

      if (endpoint) {
        uiStore.selectEndpoint(endpoint.id);
      }

      reapplySelectedDevice();
    }
  }

  function pickMonitor(candidateId: string): void {
    const candidate = $catalogMonitors.find((entry) => entry.id === candidateId);
    openMenu = null;

    if (!candidate) {
      return;
    }

    const result = deviceStore.addMonitor(device.id, candidate);
    reportIfFailed(result);

    if (result.ok) {
      const added = deviceStore.snapshot().configurations.find((configuration) => configuration.id === device.id);
      const endpoint = added?.monitors.find((monitor) => monitor.label === candidate.label);

      if (endpoint) {
        uiStore.selectEndpoint(endpoint.id);
      }

      reapplySelectedDevice();
    }
  }

  // Stereo first: it is the default/most common pick, mirroring the reference's stereo-only add.
  const busMenuSections: readonly MenuSection[] = [
    {
      items: [
        { id: "stereo", label: "Stereo Bus", detail: "2 channels" },
        { id: "mono", label: "Mono Bus", detail: "1 channel" },
        { id: "quad", label: "Quad Bus", detail: "4 channels" }
      ]
    }
  ];

  const busMenuChannels: Readonly<Record<string, number>> = { mono: 1, stereo: 2, quad: 4 };

  function pickBus(menuId: string): void {
    openMenu = null;
    const channels = busMenuChannels[menuId];

    if (!channels) {
      return;
    }

    addBus(channels);
  }

  function addBus(channels: number): void {
    const result = deviceStore.addBus(device.id, channels);
    reportIfFailed(result);

    if (result.ok) {
      const added = deviceStore.snapshot().configurations.find((configuration) => configuration.id === device.id);
      const bus = added?.outputs.at(-1);

      if (bus) {
        uiStore.selectEndpoint(bus.id);
      }

      reapplySelectedDevice();
    }
  }

  function startPortDrag(endpointId: string, channel: number, role: DragPortRole, event: PointerEvent): void {
    if (!graphElement) {
      return;
    }

    const base = graphElement.getBoundingClientRect();
    drag = {
      from: { endpointId, role },
      fromPortKey: `${endpointId}:${channel}:out`,
      point: { x: event.clientX - base.left, y: event.clientY - base.top }
    };
  }

  function handlePointerMove(event: PointerEvent): void {
    if (!drag || !graphElement) {
      return;
    }

    const base = graphElement.getBoundingClientRect();
    drag = { ...drag, point: { x: event.clientX - base.left, y: event.clientY - base.top } };
  }

  function handlePointerUp(event: PointerEvent): void {
    if (!drag) {
      return;
    }

    const active = drag;
    drag = null;

    const target = document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>("[data-port]");
    const targetEndpoint = target?.dataset.portEndpoint;
    const targetRole = target?.dataset.portRole as DragPortRole | undefined;

    if (!target || !targetEndpoint || !targetRole) {
      return;
    }

    const connection = dragConnection(active.from, { endpointId: targetEndpoint, role: targetRole });

    if (!connection) {
      return;
    }

    if (device.routes.some((route) => route.from === connection.from && route.to === connection.to)) {
      return;
    }

    const result = deviceStore.addRoute(device.id, connection.from, connection.to);
    reportIfFailed(result);

    if (result.ok) {
      const added = deviceStore.snapshot().configurations.find((configuration) => configuration.id === device.id);
      const route = added?.routes.at(-1);

      if (route) {
        uiStore.selectRoute(route.id);
      }

      reapplySelectedDevice();
    }
  }

  function handleCanvasClick(): void {
    uiStore.clearSelection();
  }
</script>

<svelte:window onpointermove={handlePointerMove} onpointerup={handlePointerUp} />

<div class="canvas-scroll">
  <div class="title-area">
    <DeviceTitle
      name={device.name}
      editing={$renameEditing}
      onBeginEdit={() => uiStore.beginRename()}
      onCommit={(name) => {
        reportIfFailed(deviceStore.renameDevice(device.id, name));
        uiStore.endRename();
      }}
      onCancel={() => uiStore.endRename()}
    />
  </div>

  <div class="headers" class:monitors-hidden={monitorsHidden}>
    <ColumnHeader
      title="Sources"
      subtitle={sourceSummary}
      addAction="menu"
      addLabel="Add source"
      onAdd={(anchor) => (openMenu = { kind: "sources", anchor })}
    />
    <ColumnHeader
      title="Output Channels"
      subtitle={`${totalBusChannels} ${totalBusChannels === 1 ? "Channel" : "Channels"}`}
      addAction="menu"
      addLabel="Add output channels"
      onAdd={(anchor) => (openMenu = { kind: "buses", anchor })}
    />
    {#if !monitorsHidden}
      <ColumnHeader
        title="Monitors"
        subtitle={monitorSummary}
        addAction="menu"
        addLabel="Add monitor"
        onAdd={(anchor) => (openMenu = { kind: "monitors", anchor })}
      />
    {/if}
  </div>

  <div
    class="graph"
    class:monitors-hidden={monitorsHidden}
    bind:this={graphElement}
    onclick={handleCanvasClick}
    role="presentation"
  >
    <CableLayer cables={renderedCables} {draftPath} onSelectRoute={(routeId) => uiStore.selectRoute(routeId)} />
    <div class="column sources">
      {#each sortedSources as endpoint (endpoint.id)}
        <SourceCard
          {endpoint}
          icon={sourceIcon(endpoint)}
          selected={$canvasSelection?.kind === "endpoint" && $canvasSelection.endpointId === endpoint.id}
          optionsExpanded={$expandedOptions.has(endpoint.id)}
          levels={$levelStore}
          volume={Math.round(deviceStore.sourceVolume(device, endpoint.id) * 100)}
          isAppSource={isAppSource(endpoint)}
          onSelect={() => uiStore.selectEndpoint(endpoint.id)}
          onToggleEnabled={(enabled) => {
            const result = deviceStore.setSourceEnabled(device.id, endpoint.id, enabled);
            reportIfFailed(result);

            if (result.ok) {
              reapplySelectedDevice();
            }
          }}
          onToggleOptions={() => uiStore.toggleOptionsExpanded(endpoint.id)}
          onVolume={(volume) => reportIfFailed(deviceStore.setSourceVolume(device.id, endpoint.id, volume / 100))}
          onMuteWhenCapturing={(value) => reportIfFailed(deviceStore.setMuteWhenCapturing(device.id, endpoint.id, value))}
          onHostBinding={(deviceName) => setHostBinding(endpoint.id, deviceName)}
          onPortDrag={(endpointId, channel, event) => startPortDrag(endpointId, channel, "source-out", event)}
        />
      {/each}
    </div>
    <div class="column buses">
      {#each device.outputs as endpoint (endpoint.id)}
        <BusBlock
          {endpoint}
          startChannel={busStartChannels.get(endpoint.id) ?? 1}
          selected={$canvasSelection?.kind === "endpoint" && $canvasSelection.endpointId === endpoint.id}
          optionsExpanded={$expandedOptions.has(endpoint.id)}
          levels={$levelStore}
          onSelect={() => uiStore.selectEndpoint(endpoint.id)}
          onToggleOptions={() => uiStore.toggleOptionsExpanded(endpoint.id)}
          onHostBinding={(deviceName) => setHostBinding(endpoint.id, deviceName)}
          onPortDrag={(endpointId, channel, event) => startPortDrag(endpointId, channel, "bus-out", event)}
        />
      {/each}
    </div>
    {#if !monitorsHidden}
      <div class="column monitors">
        {#each device.monitors as endpoint (endpoint.id)}
          <MonitorCard
            {endpoint}
            selected={$canvasSelection?.kind === "endpoint" && $canvasSelection.endpointId === endpoint.id}
            optionsExpanded={$expandedOptions.has(endpoint.id)}
            levels={$levelStore}
            onSelect={() => uiStore.selectEndpoint(endpoint.id)}
            onToggleEnabled={(enabled) => {
            const result = deviceStore.setSourceEnabled(device.id, endpoint.id, enabled);
            reportIfFailed(result);

            if (result.ok) {
              reapplySelectedDevice();
            }
          }}
            onToggleOptions={() => uiStore.toggleOptionsExpanded(endpoint.id)}
            onVolume={(volume) => reportIfFailed(deviceStore.setSourceVolume(device.id, endpoint.id, volume / 100))}
            onHostBinding={(deviceName) => setHostBinding(endpoint.id, deviceName)}
          />
        {/each}
      </div>
    {/if}
  </div>
</div>

{#if openMenu}
  <PopupMenu
    sections={openMenu.kind === "sources" ? sourceMenuSections : openMenu.kind === "buses" ? busMenuSections : monitorMenuSections}
    anchor={openMenu.anchor}
    label={openMenu.kind === "sources" ? "Add source" : openMenu.kind === "buses" ? "Add output channels" : "Add monitor"}
    emptyMessage={openMenu.kind === "sources" ? "Every detected source is already added." : "Every playback device is already added."}
    onPick={openMenu.kind === "sources" ? pickSource : openMenu.kind === "buses" ? pickBus : pickMonitor}
    onClose={() => (openMenu = null)}
  />
{/if}

<style>
  .canvas-scroll {
    flex: 1;
    overflow-y: auto;
    /* Vertical-only at and above the minimum usable width (three fixed
       200px columns); below it, scroll rather than overlap or clip. */
    overflow-x: auto;
    padding: var(--lw-canvas-pad-top) var(--lw-space-5) var(--lw-space-5);
    display: flex;
    flex-direction: column;
  }

  .title-area {
    margin-bottom: var(--lw-space-4);
  }

  .headers,
  .graph {
    display: grid;
    grid-template-columns: repeat(3, var(--lw-card-width));
    justify-content: space-between;
    column-gap: var(--lw-space-5);
  }

  .headers.monitors-hidden,
  .graph.monitors-hidden {
    grid-template-columns: repeat(2, var(--lw-card-width));
    transition: grid-template-columns var(--lw-motion-layout);
  }

  .headers {
    margin-bottom: var(--lw-column-header-to-card);
  }

  .graph {
    position: relative;
    flex: 1;
    align-content: start;
  }

  .column {
    display: flex;
    flex-direction: column;
    gap: var(--lw-card-gap);
    position: relative;
    z-index: 1;
    min-height: 120px;
  }
</style>
