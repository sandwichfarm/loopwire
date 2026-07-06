<script module lang="ts">
  import type { DeviceRowSource } from "./DeviceRow.svelte";

  export interface SidebarDevice {
    readonly id: string;
    readonly name: string;
    readonly enabled: boolean;
    readonly muted: boolean;
    readonly volume: number;
    readonly sources: readonly DeviceRowSource[];
    readonly level: number;
  }
</script>

<script lang="ts">
  import Icon from "./Icon.svelte";
  import IconButton from "./IconButton.svelte";
  import DeviceRow from "./DeviceRow.svelte";

  interface Props {
    readonly devices: readonly SidebarDevice[];
    readonly selectedId: string | undefined;
    readonly onSelect: (deviceId: string) => void;
    readonly onCreate: () => void;
    readonly onRemove: (deviceId: string) => void;
    readonly onReorder: (deviceId: string, toIndex: number) => void;
    readonly onToggleEnabled: (deviceId: string, enabled: boolean) => void;
    readonly onToggleMuted: (deviceId: string) => void;
    readonly onVolume: (deviceId: string, volume: number) => void;
    readonly onOpenSettings: () => void;
  }

  const {
    devices,
    selectedId,
    onSelect,
    onCreate,
    onRemove,
    onReorder,
    onToggleEnabled,
    onToggleMuted,
    onVolume,
    onOpenSettings
  }: Props = $props();

  let listElement: HTMLDivElement | undefined = $state();
  let drag: { readonly deviceId: string; readonly startY: number; active: boolean; toIndex: number } | null = $state(null);
  let suppressNextClick = false;

  const dragThresholdPx = 5;

  function rowPointerDown(deviceId: string, event: PointerEvent): void {
    // Controls keep their own pointer gestures (sliders, pills, buttons).
    if ((event.target as HTMLElement).closest("button, input")) {
      return;
    }

    drag = { deviceId, startY: event.clientY, active: false, toIndex: rowIndex(deviceId) };
  }

  function rowIndex(deviceId: string): number {
    return devices.findIndex((device) => device.id === deviceId);
  }

  function handlePointerMove(event: PointerEvent): void {
    if (!drag) {
      return;
    }

    if (!drag.active && Math.abs(event.clientY - drag.startY) < dragThresholdPx) {
      return;
    }

    drag = { ...drag, active: true, toIndex: insertionIndex(event.clientY) };
  }

  /** Post-removal insertion index: rows (minus the dragged one) whose midpoint is above the pointer. */
  function insertionIndex(pointerY: number): number {
    if (!listElement || !drag) {
      return 0;
    }

    const rows = [...listElement.querySelectorAll<HTMLElement>("[data-device-row]")];
    let index = 0;

    for (const row of rows) {
      if (row.dataset.deviceRow === drag.deviceId) {
        continue;
      }

      const rect = row.getBoundingClientRect();

      if (pointerY > rect.top + rect.height / 2) {
        index += 1;
      }
    }

    return index;
  }

  function handlePointerUp(): void {
    if (!drag) {
      return;
    }

    const finished = drag;
    drag = null;

    if (finished.active) {
      suppressNextClick = true;
      onReorder(finished.deviceId, finished.toIndex);
    }
  }

  function handleListClickCapture(event: MouseEvent): void {
    if (suppressNextClick) {
      suppressNextClick = false;
      event.stopPropagation();
      event.preventDefault();
    }
  }

  function rowDropState(deviceId: string): "above" | "below" | null {
    if (!drag?.active) {
      return null;
    }

    const others = devices.filter((device) => device.id !== drag!.deviceId);

    if (drag.toIndex < others.length) {
      return others[drag.toIndex]?.id === deviceId ? "above" : null;
    }

    return others.at(-1)?.id === deviceId ? "below" : null;
  }

  function handleListKeydown(event: KeyboardEvent): void {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") {
      return;
    }

    event.preventDefault();
    const index = devices.findIndex((device) => device.id === selectedId);
    const nextIndex =
      event.key === "ArrowDown" ? Math.min(devices.length - 1, index + 1) : Math.max(0, index <= 0 ? 0 : index - 1);
    const next = devices[nextIndex];

    if (next && next.id !== selectedId) {
      onSelect(next.id);
    }
  }
</script>

<svelte:window onpointermove={handlePointerMove} onpointerup={handlePointerUp} />

<aside class="sidebar">
  <header class="header">
    <span class="brand" aria-hidden="true"><Icon name="loop" size={15} /></span>
    <h2>Devices</h2>
    <IconButton icon="gear" label="Loopwire settings (Ctrl+,)" size={14} onClick={onOpenSettings} />
  </header>
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div
    class="list"
    role="listbox"
    aria-label="Virtual audio devices"
    tabindex={devices.length > 0 ? 0 : -1}
    bind:this={listElement}
    onkeydown={handleListKeydown}
    onclickcapture={handleListClickCapture}
  >
    {#each devices as device (device.id)}
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
      <div
        class="row-slot"
        class:dragging={drag?.active === true && drag.deviceId === device.id}
        class:drop-above={rowDropState(device.id) === "above"}
        class:drop-below={rowDropState(device.id) === "below"}
        data-device-row={device.id}
        role="presentation"
        onpointerdown={(event) => rowPointerDown(device.id, event)}
      >
        <DeviceRow
          name={device.name}
          enabled={device.enabled}
          muted={device.muted}
          volume={device.volume}
          sources={device.sources}
          level={device.level}
          selected={device.id === selectedId}
          onSelect={() => onSelect(device.id)}
          onToggleEnabled={(enabled) => onToggleEnabled(device.id, enabled)}
          onToggleMuted={() => onToggleMuted(device.id)}
          onVolume={(volume) => onVolume(device.id, volume)}
        />
      </div>
    {/each}
  </div>
  <footer class="footer">
    <button type="button" class="new-device" onclick={onCreate}>
      <Icon name="plus" size={14} />
      <span>New Virtual Device</span>
    </button>
    <IconButton
      icon="minus"
      label="Remove selected device"
      disabled={!selectedId}
      onClick={() => {
        if (selectedId) {
          onRemove(selectedId);
        }
      }}
    />
  </footer>
</aside>

<style>
  .sidebar {
    display: flex;
    flex-direction: column;
    width: var(--lw-sidebar-width);
    min-width: var(--lw-sidebar-width);
    height: 100%;
    background: var(--lw-sidebar-bg);
    border-right: 1px solid var(--lw-hairline);
  }

  .header {
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
    height: var(--lw-sidebar-header-height);
    padding: 0 12px;
    border-bottom: 1px solid var(--lw-hairline);
    flex: none;
  }

  .brand {
    color: var(--lw-accent);
    display: inline-flex;
  }

  .header h2 {
    font: var(--lw-text-sidebar-header);
    margin: 0;
    flex: 1;
  }

  .list {
    flex: 1;
    overflow-y: auto;
  }

  .row-slot {
    position: relative;
    touch-action: none;
  }

  .row-slot.dragging {
    opacity: 0.55;
  }

  .row-slot.drop-above::before,
  .row-slot.drop-below::after {
    content: "";
    position: absolute;
    left: 6px;
    right: 6px;
    height: 2px;
    background: var(--lw-accent);
    z-index: 1;
    pointer-events: none;
  }

  .row-slot.drop-above::before {
    top: -1px;
  }

  .row-slot.drop-below::after {
    bottom: -1px;
  }

  .list:focus-visible {
    outline: none;
    box-shadow: inset var(--lw-focus-ring);
  }

  .footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: var(--lw-footer-height);
    padding: 0 12px;
    border-top: 1px solid var(--lw-hairline);
    flex: none;
  }

  .new-device {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    border: none;
    background: transparent;
    color: var(--lw-text-primary);
    font: var(--lw-text-body);
    cursor: pointer;
    padding: 4px 6px;
    border-radius: 5px;
  }

  .new-device:hover {
    color: var(--lw-accent);
  }

  .new-device:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }
</style>
