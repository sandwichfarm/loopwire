<script lang="ts">
  import type { Toast } from "../stores/uiStore";

  interface Props {
    readonly toasts: readonly Toast[];
    readonly onDismiss: (id: number) => void;
  }

  const { toasts, onDismiss }: Props = $props();
</script>

<div class="toasts" aria-live="polite">
  {#each toasts as toast (toast.id)}
    <div class="toast" class:error={toast.kind === "error"} role="status">
      <span class="message">{toast.message}</span>
      {#if toast.undo}
        <button
          type="button"
          class="undo"
          onclick={() => {
            toast.undo?.();
            onDismiss(toast.id);
          }}
        >
          Undo
        </button>
      {/if}
      <button type="button" class="close" aria-label="Dismiss notification" onclick={() => onDismiss(toast.id)}>×</button>
    </div>
  {/each}
</div>

<style>
  .toasts {
    position: fixed;
    bottom: calc(var(--lw-footer-height) + 12px);
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    flex-direction: column;
    gap: var(--lw-space-2);
    z-index: 60;
    pointer-events: none;
  }

  .toast {
    pointer-events: auto;
    display: flex;
    align-items: center;
    gap: var(--lw-space-3);
    background: var(--lw-menu-bg);
    color: var(--lw-text-primary);
    border: 1px solid var(--lw-hairline);
    border-radius: 8px;
    box-shadow: var(--lw-menu-shadow);
    padding: 8px 12px;
    font: var(--lw-text-body);
    max-width: 420px;
  }

  .toast.error {
    border-color: var(--lw-danger);
  }

  .undo {
    border: none;
    background: transparent;
    color: var(--lw-accent);
    font: var(--lw-text-card-title);
    cursor: pointer;
    padding: 2px 4px;
  }

  .undo:focus-visible,
  .close:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
    border-radius: 4px;
  }

  .close {
    border: none;
    background: transparent;
    color: var(--lw-text-secondary);
    cursor: pointer;
    font-size: 14px;
    line-height: 1;
    padding: 2px 4px;
  }
</style>
