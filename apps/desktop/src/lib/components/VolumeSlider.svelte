<script lang="ts">
  interface Props {
    /** 0–100 */
    readonly value: number;
    readonly label: string;
    readonly showReadout?: boolean;
    readonly disabled?: boolean;
    readonly onInput: (value: number) => void;
  }

  const { value, label, showReadout = true, disabled = false, onInput }: Props = $props();

  function handleInput(event: Event): void {
    onInput(Number((event.currentTarget as HTMLInputElement).value));
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === "PageUp") {
      event.preventDefault();
      onInput(Math.min(100, value + 10));
    } else if (event.key === "PageDown") {
      event.preventDefault();
      onInput(Math.max(0, value - 10));
    }
  }
</script>

<span class="slider" class:disabled>
  <input
    type="range"
    min="0"
    max="100"
    step="1"
    {value}
    {disabled}
    aria-label={label}
    style:--fill="{value}%"
    oninput={handleInput}
    onkeydown={handleKeydown}
    onclick={(event) => event.stopPropagation()}
  />
  {#if showReadout}
    <span class="readout">{value}%</span>
  {/if}
</span>

<style>
  .slider {
    display: inline-flex;
    align-items: center;
    gap: var(--lw-space-2);
    min-width: 0;
    flex: 1;
  }

  .slider.disabled {
    opacity: 0.4;
  }

  input[type="range"] {
    appearance: none;
    -webkit-appearance: none;
    flex: 1;
    min-width: 40px;
    height: var(--lw-slider-knob);
    margin: 0;
    background: transparent;
    cursor: pointer;
  }

  input[type="range"]::-webkit-slider-runnable-track {
    height: var(--lw-slider-track);
    border-radius: 999px;
    background: linear-gradient(to right, var(--lw-accent) var(--fill), var(--lw-track) var(--fill));
  }

  input[type="range"]::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: var(--lw-slider-knob);
    height: var(--lw-slider-knob);
    margin-top: calc((var(--lw-slider-track) - var(--lw-slider-knob)) / 2);
    border-radius: 50%;
    background: var(--lw-knob);
    border: none;
    box-shadow: 0 1px 2px rgb(0 0 0 / 40%);
  }

  input[type="range"]:focus-visible {
    outline: none;
  }

  input[type="range"]:focus-visible::-webkit-slider-thumb {
    box-shadow: var(--lw-focus-ring);
  }

  .readout {
    font: var(--lw-text-body);
    color: var(--lw-text-secondary);
    min-width: 34px;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
</style>
