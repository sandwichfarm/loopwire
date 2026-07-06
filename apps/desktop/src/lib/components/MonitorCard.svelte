<script lang="ts">
  import type { AudioEndpoint } from "@loopwire/core";
  import { endpointVolume, isEndpointEnabled } from "@loopwire/core";
  import { channelLabel } from "../stores/deviceStore";
  import type { PortLevels } from "../stores/levelStore";
  import { levelFor } from "../stores/levelStore";
  import Icon from "./Icon.svelte";
  import Meter from "./Meter.svelte";
  import OptionsDisclosure from "./OptionsDisclosure.svelte";
  import PortDot from "./PortDot.svelte";
  import TogglePill from "./TogglePill.svelte";
  import VolumeSlider from "./VolumeSlider.svelte";

  interface Props {
    readonly endpoint: AudioEndpoint;
    readonly selected: boolean;
    readonly optionsExpanded: boolean;
    readonly levels: PortLevels;
    readonly onSelect: () => void;
    readonly onToggleEnabled: (enabled: boolean) => void;
    readonly onToggleOptions: () => void;
    readonly onVolume: (volume: number) => void;
  }

  const { endpoint, selected, optionsExpanded, levels, onSelect, onToggleEnabled, onToggleOptions, onVolume }: Props =
    $props();

  const enabled = $derived(isEndpointEnabled(endpoint));
  const volume = $derived(Math.round(endpointVolume(endpoint) * 100));
</script>

<!-- Cards are selectable composite widgets: focusable groups whose click/Enter selects; inner controls remain independently interactive. -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
<article
  class="card"
  class:selected
  class:off={!enabled}
  data-endpoint={endpoint.id}
  role="group"
  aria-label={`Monitor ${endpoint.label}`}
  tabindex="0"
  onclick={onSelect}
  onkeydown={(event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect();
    }
  }}
>
  <header class="header">
    <span class="title" title={endpoint.label}>{endpoint.label}</span>
    <TogglePill on={enabled} label={`${endpoint.label} on or off`} onToggle={onToggleEnabled} />
  </header>
  <div class="body">
    <div class="channels">
      {#each Array.from({ length: endpoint.channels }, (_, index) => index + 1) as channel (channel)}
        <div class="channel-row">
          <PortDot
            endpointId={endpoint.id}
            {channel}
            side="in"
            role="monitor-in"
            active={enabled}
            label={`${endpoint.label} channel ${channel} input port`}
          />
          <Meter level={levelFor(levels, endpoint.id, channel)} label={`${endpoint.label} channel ${channel} level`} />
          <span class="channel-label">{channelLabel(channel)}</span>
        </div>
      {/each}
    </div>
    <span class="icon" aria-hidden="true"><Icon name="speaker" size={26} /></span>
  </div>
  <OptionsDisclosure expanded={optionsExpanded} onToggle={onToggleOptions}>
    <div class="volume-row">
      <span class="volume-label">Volume</span>
      <VolumeSlider value={volume} label={`${endpoint.label} volume`} onInput={onVolume} />
    </div>
    <p class="note">Applied to the host device when this configuration is applied.</p>
  </OptionsDisclosure>
</article>

<style>
  .card {
    width: var(--lw-card-width);
    background: var(--lw-card-bg);
    border: 1px solid var(--lw-hairline);
    border-radius: var(--lw-card-radius);
    box-shadow: var(--lw-card-shadow);
    position: relative;
  }

  .card.selected {
    outline: 2px solid var(--lw-accent);
  }

  .card:focus-visible {
    outline: 2px solid var(--lw-accent);
  }

  .card.off .body {
    opacity: 0.55;
  }

  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--lw-space-2);
    height: var(--lw-card-header-height);
    padding: 0 10px;
    background: var(--lw-card-header-bg);
    border-radius: var(--lw-card-radius) var(--lw-card-radius) 0 0;
  }

  .title {
    font: var(--lw-text-card-title);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
  }

  .body {
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
    padding: 10px 8px 10px 10px;
  }

  .icon {
    width: 40px;
    height: 40px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: var(--lw-text-secondary);
    background: var(--lw-options-bg);
    border-radius: 8px;
    flex: none;
  }

  .channels {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: var(--lw-channel-row-gap);
    min-width: 0;
  }

  .channel-row {
    position: relative;
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
    height: var(--lw-channel-row-height);
    padding-left: 6px;
  }

  .channel-label {
    font: var(--lw-text-body);
    color: var(--lw-text-secondary);
    min-width: 28px;
    font-variant-numeric: tabular-nums;
  }

  .volume-row {
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
  }

  .volume-label {
    font: var(--lw-text-body);
    color: var(--lw-text-secondary);
    min-width: 44px;
  }

  .note {
    margin: 0;
    font: var(--lw-text-subtitle);
    color: var(--lw-text-dim);
  }
</style>
