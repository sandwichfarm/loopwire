<script module lang="ts">
  export interface RenderedCable {
    readonly id: string;
    readonly routeId: string;
    readonly path: string;
    readonly state: "live" | "dimmed" | "selected";
  }
</script>

<script lang="ts">
  interface Props {
    readonly cables: readonly RenderedCable[];
    /** Provisional drag cable path, while connecting ports. */
    readonly draftPath: string | null;
    readonly onSelectRoute: (routeId: string) => void;
  }

  const { cables, draftPath, onSelectRoute }: Props = $props();
</script>

<svg class="cable-layer" aria-hidden="true">
  {#each cables as cable (cable.id)}
    <!-- wide invisible twin path gives the 6px hit slop for clicks -->
    <path
      class="hit"
      d={cable.path}
      role="button"
      tabindex="-1"
      aria-label="Select cable"
      onclick={(event) => {
        event.stopPropagation();
        onSelectRoute(cable.routeId);
      }}
      onkeydown={(event) => {
        if (event.key === "Enter") {
          onSelectRoute(cable.routeId);
        }
      }}
    />
    <path class="cable {cable.state}" d={cable.path} />
  {/each}
  {#if draftPath}
    <path class="cable draft" d={draftPath} />
  {/if}
</svg>

<style>
  .cable-layer {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
    z-index: 0;
    pointer-events: none;
  }

  path {
    fill: none;
  }

  .hit {
    stroke: transparent;
    stroke-width: 12px;
    pointer-events: stroke;
    cursor: pointer;
  }

  .cable {
    stroke: var(--lw-accent);
    stroke-width: var(--lw-cable-stroke);
    pointer-events: none;
  }

  .cable.dimmed {
    stroke: var(--lw-cable-dim);
  }

  .cable.selected {
    stroke: var(--lw-accent-strong);
    stroke-width: 3px;
  }

  .cable.draft {
    stroke: var(--lw-accent);
    stroke-dasharray: 6 4;
  }
</style>
