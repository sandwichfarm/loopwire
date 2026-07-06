<script lang="ts">
  import { onMount } from "svelte";
  import "./lib/tokens.css";
  import { deviceStore, hostCatalog, runtimeService, themeService, uiStore } from "./lib/app";
  import AppShell from "./lib/components/AppShell.svelte";

  onMount(() => {
    themeService.restore();
    void boot();
  });

  async function boot(): Promise<void> {
    await deviceStore.restore();
    await runtimeService.detectBackends();
    await hostCatalog.refresh(deviceStore.snapshot().selectedBackend);
    await runtimeService.refreshStartupStatus();
    await runtimeService.verifyStartup();
  }

  function handleKeydown(event: KeyboardEvent): void {
    if ((event.ctrlKey || event.metaKey) && event.key === ",") {
      event.preventDefault();
      uiStore.settingsOpen.update((open) => !open);
    }
  }
</script>

<svelte:head>
  <title>Loopwire</title>
</svelte:head>

<svelte:window onkeydown={handleKeydown} />

<AppShell />
