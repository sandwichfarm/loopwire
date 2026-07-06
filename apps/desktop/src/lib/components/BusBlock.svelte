<script lang="ts">
  import type { AudioEndpoint } from "@loopwire/core";
  import { channelLabel } from "../stores/deviceStore";
  import type { PortLevels } from "../stores/levelStore";
  import { levelFor } from "../stores/levelStore";
  import Meter from "./Meter.svelte";
  import PortDot from "./PortDot.svelte";

  interface Props {
    readonly endpoint: AudioEndpoint;
    /** 1-based channel number of this bus's first channel across the device. */
    readonly startChannel: number;
    readonly selected: boolean;
    readonly levels: PortLevels;
    readonly onSelect: () => void;
    readonly onPortDrag: (endpointId: string, channel: number, event: PointerEvent) => void;
  }

  const { endpoint, startChannel, selected, levels, onSelect, onPortDrag }: Props = $props();
</script>

<!-- Cards are selectable composite widgets: focusable groups whose click/Enter selects; inner controls remain independently interactive. -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
<article
  class="bus"
  class:selected
  data-endpoint={endpoint.id}
  role="group"
  aria-label={`Output channels ${endpoint.label}`}
  tabindex="0"
  onclick={(event) => {
    event.stopPropagation();
    onSelect();
  }}
  onkeydown={(event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect();
    }
  }}
>
  <header class="header">
    <span class="title">{endpoint.label}</span>
  </header>
  <div class="channels">
    {#each Array.from({ length: endpoint.channels }, (_, index) => index + 1) as channel (channel)}
      <div class="channel-row">
        <PortDot
          endpointId={endpoint.id}
          {channel}
          side="in"
          role="bus-in"
          active={true}
          label={`${endpoint.label} channel ${channel} input port`}
        />
        <span class="channel-label">Channel {channelLabel(startChannel + channel - 1)}</span>
        <Meter
          level={levelFor(levels, endpoint.id, channel)}
          size="bus"
          label={`${endpoint.label} channel ${channel} level`}
        />
        <PortDot
          endpointId={endpoint.id}
          {channel}
          side="out"
          role="bus-out"
          active={true}
          label={`${endpoint.label} channel ${channel} output port`}
          onDragStart={(event) => onPortDrag(endpoint.id, channel, event)}
        />
      </div>
    {/each}
  </div>
</article>

<style>
  .bus {
    width: var(--lw-card-width);
    background: var(--lw-card-bg);
    border: 1px solid var(--lw-hairline);
    border-radius: var(--lw-card-radius);
    box-shadow: var(--lw-card-shadow);
    position: relative;
  }

  .bus.selected {
    outline: 2px solid var(--lw-accent);
  }

  .bus:focus-visible {
    outline: 2px solid var(--lw-accent);
  }

  .header {
    display: flex;
    align-items: center;
    height: var(--lw-card-header-height);
    padding: 0 10px;
    background: var(--lw-card-header-bg);
    border-radius: var(--lw-card-radius) var(--lw-card-radius) 0 0;
  }

  .title {
    font: var(--lw-text-card-title);
  }

  .channels {
    display: flex;
    flex-direction: column;
    gap: var(--lw-channel-row-gap);
    padding: 10px 8px;
  }

  .channel-row {
    position: relative;
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
    height: var(--lw-channel-row-height);
    padding: 0 6px;
  }

  .channel-label {
    font: var(--lw-text-body);
    color: var(--lw-text-secondary);
    flex: 1;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
</style>
