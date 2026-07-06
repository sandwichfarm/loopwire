<script lang="ts">
  interface Props {
    /** 0–1 linear level; 0 renders the silent track. */
    readonly level: number;
    readonly size?: "card" | "bus" | "mini";
    readonly label: string;
  }

  const { level, size = "card", label }: Props = $props();

  const clamped = $derived(Math.max(0, Math.min(1, level)));
</script>

<span
  class="meter {size}"
  role="meter"
  aria-label={label}
  aria-valuemin={0}
  aria-valuemax={100}
  aria-valuenow={Math.round(clamped * 100)}
>
  <span class="fill" style:width="{clamped * 100}%"></span>
</span>

<style>
  .meter {
    display: inline-block;
    position: relative;
    height: var(--lw-meter-height);
    width: var(--lw-meter-width-card);
    border-radius: 999px;
    background: var(--lw-track);
    overflow: hidden;
    flex: none;
  }

  .meter.bus {
    width: var(--lw-meter-width-bus);
  }

  .meter.mini {
    width: var(--lw-meter-mini-width);
    height: var(--lw-meter-mini-height);
  }

  .fill {
    position: absolute;
    inset: 0 auto 0 0;
    border-radius: inherit;
    background: var(--lw-accent);
    transition: width var(--lw-motion-fast);
  }
</style>
