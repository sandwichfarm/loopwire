<script module lang="ts">
  import type { IconName } from "./Icon.svelte";

  export interface DeviceRowSource {
    readonly icon: IconName;
    readonly label: string;
  }
</script>

<script lang="ts">
  import Icon from "./Icon.svelte";
  import IconButton from "./IconButton.svelte";
  import Meter from "./Meter.svelte";
  import TogglePill from "./TogglePill.svelte";
  import VolumeSlider from "./VolumeSlider.svelte";

  interface Props {
    readonly name: string;
    readonly enabled: boolean;
    readonly muted: boolean;
    /** 0–100 */
    readonly volume: number;
    readonly sources: readonly DeviceRowSource[];
    /** 0–1 live level; 0/absent hides the mini meter. */
    readonly level: number;
    readonly selected: boolean;
    readonly onSelect: () => void;
    readonly onToggleEnabled: (enabled: boolean) => void;
    readonly onToggleMuted: () => void;
    readonly onVolume: (volume: number) => void;
  }

  const { name, enabled, muted, volume, sources, level, selected, onSelect, onToggleEnabled, onToggleMuted, onVolume }: Props =
    $props();

  const summary = $derived(sources.map((source) => source.label).join(", "));
</script>

<div
  class="row"
  class:selected
  class:off={!enabled}
  role="option"
  aria-selected={selected}
  tabindex="-1"
  onclick={onSelect}
  onkeydown={(event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect();
    }
  }}
>
  <div class="line title-line">
    <span class="name">{name}</span>
    <TogglePill on={enabled} label={`${name} on or off`} onToggle={onToggleEnabled} />
  </div>
  <div class="line summary-line">
    <span class="icons" aria-hidden="true">
      {#each sources.slice(0, 3) as source (source.label)}
        <Icon name={source.icon} size={13} />
      {/each}
    </span>
    <span class="summary" title={summary}>{summary || "No sources"}</span>
    {#if level > 0}
      <Meter {level} size="mini" label={`${name} level`} />
    {/if}
  </div>
  <div class="line control-line">
    <IconButton
      icon={muted ? "speaker-off" : "speaker"}
      label={muted ? `Unmute ${name}` : `Mute ${name}`}
      danger={muted}
      pressed={muted}
      size={14}
      onClick={onToggleMuted}
    />
    <VolumeSlider value={volume} label={`${name} volume`} onInput={onVolume} />
  </div>
</div>

<style>
  .row {
    padding: 10px 12px;
    display: flex;
    flex-direction: column;
    gap: var(--lw-space-2);
    cursor: default;
    border-bottom: 1px solid var(--lw-hairline);
  }

  .row.selected {
    background: var(--lw-selection-tint);
  }

  .row.off .summary,
  .row.off .icons {
    opacity: 0.55;
  }

  .row:focus-visible {
    outline: none;
    box-shadow: inset var(--lw-focus-ring);
  }

  .line {
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
    min-width: 0;
  }

  .name {
    font: var(--lw-text-sidebar-header);
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .icons {
    display: inline-flex;
    gap: 3px;
    color: var(--lw-text-secondary);
    flex: none;
  }

  .summary {
    font: var(--lw-text-subtitle);
    color: var(--lw-text-secondary);
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    white-space: normal;
  }
</style>
