<script lang="ts">
  import { tick } from "svelte";
  import IconButton from "./IconButton.svelte";

  interface Props {
    readonly name: string;
    readonly editing: boolean;
    readonly onBeginEdit: () => void;
    readonly onCommit: (name: string) => void;
    readonly onCancel: () => void;
  }

  const { name, editing, onBeginEdit, onCommit, onCancel }: Props = $props();

  let input: HTMLInputElement | undefined = $state();
  let draft = $state("");

  $effect(() => {
    if (editing) {
      draft = name;
      void tick().then(() => {
        input?.focus();
        input?.select();
      });
    }
  });

  function commit(): void {
    onCommit(draft.trim() || name);
  }
</script>

{#if editing}
  <input
    class="rename"
    type="text"
    aria-label="Device name"
    bind:this={input}
    bind:value={draft}
    onkeydown={(event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        commit();
      } else if (event.key === "Escape") {
        event.preventDefault();
        onCancel();
      }
    }}
    onblur={commit}
  />
{:else}
  <div class="title-row">
    <h1>{name}</h1>
    <IconButton icon="pencil" label={`Rename ${name}`} size={15} onClick={onBeginEdit} />
  </div>
{/if}

<style>
  .title-row {
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
    min-height: var(--lw-field-height);
  }

  h1 {
    font: var(--lw-text-title);
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
  }

  .rename {
    width: 100%;
    height: var(--lw-field-height);
    border-radius: var(--lw-field-radius);
    border: none;
    background: var(--lw-card-bg);
    color: var(--lw-text-primary);
    font: var(--lw-text-title);
    padding: 0 10px;
    box-shadow: var(--lw-focus-ring);
    outline: none;
  }

  .rename::selection {
    background: var(--lw-selection-tint);
  }
</style>
