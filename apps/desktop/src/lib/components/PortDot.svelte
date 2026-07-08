<script lang="ts">
  import { portId, type DragPortRole, type PortSide } from "../cables/geometry";

  interface Props {
    readonly endpointId: string;
    readonly channel: number;
    readonly side: PortSide;
    readonly role: DragPortRole;
    readonly active: boolean;
    readonly label: string;
    readonly onDragStart?: (event: PointerEvent) => void;
  }

  const { endpointId, channel, side, role, active, label, onDragStart }: Props = $props();
</script>

<span
  class="port {side}"
  class:active
  data-port={portId(endpointId, channel, side)}
  data-port-role={role}
  data-port-endpoint={endpointId}
  role="button"
  tabindex="-1"
  aria-label={label}
  onpointerdown={(event) => {
    event.stopPropagation();
    event.preventDefault();
    onDragStart?.(event);
  }}
>
  <!-- SVG instead of CSS border-radius/box-shadow: WebKitGTK aliases tiny CSS
       circles into pixelated blobs; SVG circles stay smooth. -->
  <svg class="glyph" viewBox="0 0 12 12" aria-hidden="true">
    {#if active}
      <circle cx="6" cy="6" r="4.75" fill="none" stroke="var(--lw-accent)" stroke-width="1.25" />
    {/if}
    <circle cx="6" cy="6" r="3.5" fill="var(--lw-track)" />
  </svg>
</span>

<style>
  .port {
    position: absolute;
    top: 50%;
    width: var(--lw-port-size);
    height: var(--lw-port-size);
    transform: translateY(-50%);
    cursor: crosshair;
    touch-action: none;
  }

  .glyph {
    position: absolute;
    top: 50%;
    left: 50%;
    width: 12px;
    height: 12px;
    transform: translate(-50%, -50%);
    overflow: visible;
    pointer-events: none;
  }

  .port::after {
    /* generous invisible hit target for drags */
    content: "";
    position: absolute;
    inset: -6px;
  }

  .port.out {
    right: calc(var(--lw-port-size) / -2);
  }

  .port.in {
    left: calc(var(--lw-port-size) / -2);
  }
</style>
