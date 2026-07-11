<script lang="ts">
  interface Props {
    readonly on: boolean;
    readonly disabled?: boolean;
    readonly label: string;
    readonly onToggle: (on: boolean) => void;
  }

  const { on, disabled = false, label, onToggle }: Props = $props();
</script>

<button
  type="button"
  role="switch"
  aria-checked={on}
  aria-label={label}
  class="pill"
  class:on
  {disabled}
  onclick={(event) => {
    event.stopPropagation();
    onToggle(!on);
  }}
>
  <span class="text">{on ? "On" : "Off"}</span>
  <span class="knob"></span>
</button>

<style>
  .pill {
    display: inline-flex;
    align-items: center;
    justify-content: space-between;
    width: var(--lw-pill-width);
    height: var(--lw-pill-height);
    padding: 2px 3px;
    border-radius: 999px;
    border: 1px solid var(--lw-danger);
    background: var(--lw-danger);
    color: var(--lw-knob);
    font: var(--lw-text-pill);
    cursor: pointer;
    flex-direction: row-reverse;
  }

  .pill.on {
    flex-direction: row;
    background: transparent;
    border-color: var(--lw-accent);
    color: var(--lw-accent);
  }

  .pill:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .pill:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }

  .text {
    padding: 0 3px;
  }

  .knob {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--lw-knob);
    flex: none;
  }
</style>
