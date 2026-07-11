<script lang="ts">
  import Icon, { type IconName } from "./Icon.svelte";

  interface Props {
    readonly label: string;
    readonly icon?: IconName;
    readonly disabled?: boolean;
    readonly onClick: () => void;
  }

  const { label, icon, disabled = false, onClick }: Props = $props();
</script>

<button type="button" class="button" {disabled} onclick={onClick}>
  {#if icon}
    <Icon name={icon} size={13} />
  {/if}
  <span>{label}</span>
</button>

<style>
  .button {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: var(--lw-footer-button-height);
    padding: 0 10px;
    border: 1px solid var(--lw-hairline);
    border-radius: var(--lw-footer-button-radius);
    background: var(--lw-footer-button-bg);
    color: var(--lw-text-primary);
    font: var(--lw-text-body);
    cursor: pointer;
  }

  .button:hover:not(:disabled) {
    filter: brightness(1.1);
  }

  .button:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .button:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }
</style>
