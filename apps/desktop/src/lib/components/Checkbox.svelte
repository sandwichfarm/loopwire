<script lang="ts">
  interface Props {
    readonly checked: boolean;
    readonly label: string;
    readonly disabled?: boolean;
    readonly onChange: (checked: boolean) => void;
  }

  const { checked, label, disabled = false, onChange }: Props = $props();
</script>

<label class="checkbox" class:disabled>
  <input
    type="checkbox"
    {checked}
    {disabled}
    onchange={(event) => onChange((event.currentTarget as HTMLInputElement).checked)}
  />
  <span class="box" aria-hidden="true">
    {#if checked}
      <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="currentColor" stroke-width="1.8">
        <path d="M1.8 5.2 4 7.4 8.2 2.8" />
      </svg>
    {/if}
  </span>
  <span class="text">{label}</span>
</label>

<style>
  .checkbox {
    display: inline-flex;
    align-items: center;
    gap: var(--lw-space-2);
    cursor: pointer;
    font: var(--lw-text-body);
    color: var(--lw-text-primary);
  }

  .checkbox.disabled {
    opacity: 0.4;
    cursor: default;
  }

  input {
    position: absolute;
    opacity: 0;
    width: 1px;
    height: 1px;
  }

  .box {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 14px;
    height: 14px;
    border-radius: 4px;
    border: 1px solid var(--lw-track);
    background: transparent;
    color: var(--lw-knob);
    flex: none;
  }

  input:checked + .box {
    background: var(--lw-accent);
    border-color: var(--lw-accent);
  }

  input:focus-visible + .box {
    box-shadow: var(--lw-focus-ring);
  }
</style>
