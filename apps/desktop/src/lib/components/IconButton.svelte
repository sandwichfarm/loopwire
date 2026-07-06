<script lang="ts">
  import Icon, { type IconName } from "./Icon.svelte";

  interface Props {
    readonly icon: IconName;
    readonly label: string;
    readonly size?: number;
    readonly disabled?: boolean;
    readonly danger?: boolean;
    readonly pressed?: boolean;
    readonly onClick: (event: MouseEvent) => void;
  }

  const { icon, label, size = 16, disabled = false, danger = false, pressed, onClick }: Props = $props();
</script>

<button
  type="button"
  class="icon-button"
  class:danger
  aria-label={label}
  title={label}
  aria-pressed={pressed}
  {disabled}
  onclick={(event) => {
    event.stopPropagation();
    onClick(event);
  }}
>
  <Icon name={icon} {size} />
</button>

<style>
  .icon-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 2px;
    border: none;
    border-radius: 4px;
    background: transparent;
    color: var(--lw-text-secondary);
    cursor: pointer;
    transition: color var(--lw-motion-fast);
    flex: none;
  }

  .icon-button:hover:not(:disabled) {
    color: var(--lw-text-primary);
  }

  .icon-button.danger {
    color: var(--lw-danger);
  }

  .icon-button:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .icon-button:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }
</style>
