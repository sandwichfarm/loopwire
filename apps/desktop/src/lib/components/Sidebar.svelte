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
    readonly onToggleEnabled: (deviceId: string, enabled: boolean) => void;
    readonly onToggleMuted: (deviceId: string) => void;
    readonly onVolume: (deviceId: string, volume: number) => void;
    readonly onOpenSettings: () => void;
  }

  const { devices, selectedId, onSelect, onCreate, onRemove, onToggleEnabled, onToggleMuted, onVolume, onOpenSettings }: Props =
    $props();

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

<aside class="sidebar">
  <header class="header">
    <span class="brand" aria-hidden="true"><Icon name="loop" size={15} /></span>
    <h2>Devices</h2>
    <IconButton icon="gear" label="Loopwire settings (Ctrl+,)" size={14} onClick={onOpenSettings} />
  </header>
  <div
    class="list"
    role="listbox"
    aria-label="Virtual audio devices"
    tabindex={devices.length > 0 ? 0 : -1}
    onkeydown={handleListKeydown}
  >
    {#each devices as device (device.id)}
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
