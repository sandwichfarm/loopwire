<script lang="ts">
  import Icon from "./Icon.svelte";

  interface Props {
    readonly title: string;
    readonly subtitle: string;
    readonly addAction: "menu" | "instant" | "none";
    readonly addLabel?: string;
    readonly onAdd?: (anchor: HTMLElement) => void;
  }

  const { title, subtitle, addAction, addLabel, onAdd }: Props = $props();
</script>

<div class="column-header">
  <div class="text">
    <span class="title">{title}</span>
    <span class="subtitle">{subtitle}</span>
  </div>
  {#if addAction !== "none"}
    <button
      type="button"
      class="add"
      aria-label={addLabel ?? `Add to ${title}`}
      aria-haspopup={addAction === "menu" ? "menu" : undefined}
      onclick={(event) => onAdd?.(event.currentTarget as HTMLElement)}
    >
      <Icon name="plus" size={16} />
      {#if addAction === "menu"}
        <Icon name="chevron-down" size={9} />
      {/if}
    </button>
  {/if}
</div>

<style>
  .column-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--lw-space-2);
    width: var(--lw-card-width);
  }

  .text {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .title {
    font: var(--lw-text-column-header);
  }

  .subtitle {
    font: var(--lw-text-subtitle);
    color: var(--lw-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .add {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    border: none;
    background: transparent;
    color: var(--lw-text-secondary);
    cursor: pointer;
    padding: 2px;
    border-radius: 4px;
    flex: none;
  }

  .add:hover {
    color: var(--lw-accent);
  }

  .add:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }
</style>
