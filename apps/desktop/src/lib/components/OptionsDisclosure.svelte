<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "./Icon.svelte";

  interface Props {
    readonly expanded: boolean;
    readonly onToggle: () => void;
    readonly children: Snippet;
  }

  const { expanded, onToggle, children }: Props = $props();
</script>

<div class="options" class:expanded>
  <button
    type="button"
    class="toggle"
    aria-expanded={expanded}
    onclick={(event) => {
      event.stopPropagation();
      onToggle();
    }}
  >
    <Icon name={expanded ? "chevron-down" : "chevron-right"} size={11} />
    <span>Options</span>
  </button>
  {#if expanded}
    <div class="content">
      {@render children()}
    </div>
  {/if}
</div>

<style>
  .options {
    background: var(--lw-options-bg);
    border-top: 1px solid var(--lw-hairline);
    border-radius: 0 0 var(--lw-card-radius) var(--lw-card-radius);
  }

  .toggle {
    display: flex;
    align-items: center;
    gap: 5px;
    width: 100%;
    height: 24px;
    padding: 0 10px;
    border: none;
    background: transparent;
    color: var(--lw-text-secondary);
    font: var(--lw-text-body);
    cursor: pointer;
  }

  .toggle:hover {
    color: var(--lw-text-primary);
  }

  .toggle:focus-visible {
    outline: none;
    box-shadow: inset var(--lw-focus-ring);
  }

  .content {
    padding: 4px 10px 10px 26px;
    display: flex;
    flex-direction: column;
    gap: var(--lw-space-2);
  }
</style>
