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
></span>

<style>
  .port {
    position: absolute;
    top: 50%;
    width: var(--lw-port-size);
    height: var(--lw-port-size);
    border-radius: 50%;
    background: var(--lw-track);
    transform: translateY(-50%);
    cursor: crosshair;
    touch-action: none;
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

  .port.active {
    box-shadow: 0 0 0 1.5px var(--lw-accent);
  }
</style>
