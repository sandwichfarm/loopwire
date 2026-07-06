<script lang="ts">
  import { isConfigurationEnabled, isConfigurationMuted, configurationVolume } from "@loopwire/core";
  import { deviceStore, levelStore, runtimeService, uiStore } from "../app";
  import { peakLevelFor } from "../stores/levelStore";
  import type { SidebarDevice } from "./Sidebar.svelte";
  import type { IconName } from "./Icon.svelte";
  import CanvasFooter from "./CanvasFooter.svelte";
  import DeviceCanvas from "./DeviceCanvas.svelte";
  import EmptyState from "./EmptyState.svelte";
  import SettingsWindow from "./SettingsWindow.svelte";
  import Sidebar from "./Sidebar.svelte";
  import Toasts from "./Toasts.svelte";

  const { devices, selectedDevice } = deviceStore;
  const { canvasSelection, monitorsHiddenDevices, settingsOpen, toasts } = uiStore;

  const sidebarDevices = $derived.by((): readonly SidebarDevice[] =>
    $devices.map((device) => ({
      id: device.id,
      name: device.name,
      enabled: isConfigurationEnabled(device),
      muted: isConfigurationMuted(device),
      volume: Math.round(configurationVolume(device) * 100),
      sources: device.inputs.map((input) => ({
        icon: sidebarSourceIcon(input.id, input.label, input.deviceName),
        label: input.label
      })),
      level: Math.max(...device.outputs.map((output) => peakLevelFor($levelStore, output.id, output.channels)), 0)
    }))
  );

  function sidebarSourceIcon(id: string, label: string, deviceName: string | undefined): IconName {
    if (id === "pass-thru") {
      return "loop";
    }

    if (/mic/i.test(label) || /mic|capture/i.test(deviceName ?? "")) {
      return "mic";
    }

    return "app";
  }

  function reportIfFailed(result: { readonly ok: boolean; readonly message?: string }): void {
    if (!result.ok && result.message) {
      uiStore.pushToast("error", result.message);
    }
  }

  function createDevice(): void {
    const { result } = deviceStore.createDevice();
    reportIfFailed(result);

    if (result.ok) {
      uiStore.clearSelection();
      uiStore.beginRename();
    }
  }

  function removeDevice(deviceId: string): void {
    const snapshot = deviceStore.snapshot();
    const { result, removed } = deviceStore.removeDevice(deviceId);
    reportIfFailed(result);

    if (result.ok && removed) {
      uiStore.clearSelection();
      uiStore.pushToast("undo", `Removed ${removed.name}.`, () => deviceStore.restoreSnapshot(snapshot));
    }
  }

  function selectDevice(deviceId: string): void {
    if (deviceId === $selectedDevice?.id) {
      return;
    }

    uiStore.clearSelection();
    uiStore.endRename();
    void runtimeService.switchDevice(deviceId);
  }

  function deleteCanvasSelection(): void {
    const device = $selectedDevice;
    const selection = $canvasSelection;

    if (!device || !selection) {
      return;
    }

    if (selection.kind === "route") {
      reportIfFailed(deviceStore.removeRoute(device.id, selection.routeId));
      uiStore.clearSelection();
      return;
    }

    const endpointId = selection.endpointId;
    const result = device.inputs.some((input) => input.id === endpointId)
      ? deviceStore.removeSource(device.id, endpointId)
      : device.outputs.some((output) => output.id === endpointId)
        ? deviceStore.removeBus(device.id, endpointId)
        : deviceStore.removeMonitor(device.id, endpointId);

    reportIfFailed(result);

    if (result.ok) {
      uiStore.clearSelection();
    }
  }

  function handleKeydown(event: KeyboardEvent): void {
    const target = event.target as HTMLElement | null;
    const inField =
      target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target?.isContentEditable === true;

    if ((event.key === "Delete" || event.key === "Backspace") && !inField && $canvasSelection) {
      event.preventDefault();
      deleteCanvasSelection();
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="shell">
  <Sidebar
    devices={sidebarDevices}
    selectedId={$selectedDevice?.id}
    onSelect={selectDevice}
    onCreate={createDevice}
    onRemove={removeDevice}
    onToggleEnabled={(deviceId, enabled) => reportIfFailed(deviceStore.setDeviceEnabled(deviceId, enabled))}
    onToggleMuted={(deviceId) => {
      const device = $devices.find((candidate) => candidate.id === deviceId);
      if (device) {
        reportIfFailed(deviceStore.setDeviceMuted(deviceId, !isConfigurationMuted(device)));
      }
    }}
    onVolume={(deviceId, volume) => reportIfFailed(deviceStore.setDeviceVolume(deviceId, volume / 100))}
    onOpenSettings={() => settingsOpen.set(true)}
  />

  <main class="canvas-area">
    {#if $selectedDevice}
      <DeviceCanvas device={$selectedDevice} />
      <CanvasFooter
        canDelete={$canvasSelection !== null}
        monitorsHidden={$monitorsHiddenDevices.has($selectedDevice.id)}
        onDelete={deleteCanvasSelection}
        onToggleMonitors={() => {
          const device = $selectedDevice;

          if (!device) {
            return;
          }

          const hidingNow = !$monitorsHiddenDevices.has(device.id);
          const selection = $canvasSelection;

          if (
            hidingNow &&
            selection?.kind === "endpoint" &&
            device.monitors.some((monitor) => monitor.id === selection.endpointId)
          ) {
            uiStore.clearSelection();
          }

          uiStore.toggleMonitorsHidden(device.id);
        }}
      />
    {:else}
      <EmptyState />
    {/if}
  </main>
</div>

{#if $settingsOpen}
  <SettingsWindow onClose={() => settingsOpen.set(false)} />
{/if}

<Toasts toasts={$toasts} onDismiss={(id) => uiStore.dismissToast(id)} />

<style>
  .shell {
    display: flex;
    height: 100%;
    min-width: 0;
    background: var(--lw-canvas-bg);
  }

  .canvas-area {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
  }
</style>
