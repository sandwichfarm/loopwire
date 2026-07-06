<script lang="ts">
  import { tick } from "svelte";
  import { deviceStore, runtimeService, themeService, hostCatalog, uiStore } from "../app";
  import { displayBackendName } from "../services/runtime";
  import { hasTauriRuntime } from "../services/statePersistence";
  import type { ThemeMode } from "../services/theme";

  interface Props {
    readonly onClose: () => void;
  }

  const { onClose }: Props = $props();

  const { mode: themeMode } = themeService;
  const { backendCandidates, detectionNote, applyMode, status, note, busy, startup, backgroundStartup } = runtimeService;
  const appState = deviceStore.state;

  const desktop = hasTauriRuntime();

  let dialog: HTMLDivElement | undefined = $state();

  $effect(() => {
    void tick().then(() => dialog?.querySelector<HTMLElement>("button, input, [tabindex]")?.focus());
  });

  const themeOptions: readonly { readonly value: ThemeMode; readonly label: string }[] = [
    { value: "system", label: "Match System" },
    { value: "light", label: "Light" },
    { value: "dark", label: "Dark" }
  ];

  async function chooseBackend(event: Event): Promise<void> {
    const kind = (event.currentTarget as HTMLSelectElement).value;

    if (!kind) {
      return;
    }

    const ok = await runtimeService.chooseBackend(kind as never);

    if (ok) {
      await hostCatalog.refresh(deviceStore.snapshot().selectedBackend);
    }
  }

  function toggleApplyMode(): void {
    runtimeService.setApplyMode($applyMode === "preview" ? "live" : "preview");
  }
</script>

<div
  class="backdrop"
  role="presentation"
  onclick={(event) => {
    if (event.target === event.currentTarget) {
      onClose();
    }
  }}
></div>

<div
  class="window"
  role="dialog"
  aria-modal="true"
  aria-label="Loopwire settings"
  tabindex="-1"
  bind:this={dialog}
  onkeydown={(event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    }
  }}
>
  <header class="titlebar">
    <h2>Settings</h2>
    <button type="button" class="close" aria-label="Close settings" onclick={onClose}>×</button>
  </header>

  <div class="content">
    <section aria-labelledby="settings-appearance">
      <h3 id="settings-appearance">Appearance</h3>
      <div class="theme-picker" role="radiogroup" aria-label="Theme">
        {#each themeOptions as option (option.value)}
          <button
            type="button"
            class="theme-tile"
            role="radio"
            aria-checked={$themeMode === option.value}
            onclick={() => themeService.setMode(option.value)}
          >
            <span class="preview {option.value}" aria-hidden="true"></span>
            <span>{option.label}</span>
          </button>
        {/each}
      </div>
    </section>

    <section aria-labelledby="settings-backend">
      <h3 id="settings-backend">Audio Backend</h3>
      <p class="caption">{$detectionNote}</p>
      <div class="field-row">
        <label for="backend-select">Backend</label>
        <select id="backend-select" value={$appState.selectedBackend ?? ""} disabled={$busy} onchange={chooseBackend}>
          <option value="" disabled>Choose a backend</option>
          {#each $backendCandidates as candidate (candidate.kind)}
            <option value={candidate.kind} disabled={candidate.availability !== "available"}>
              {candidate.displayName}{candidate.availability === "available" ? "" : ` — ${candidate.reason ?? "unavailable"}`}
            </option>
          {/each}
        </select>
      </div>
      <div class="field-row">
        <label for="apply-mode">Host apply</label>
        <button id="apply-mode" type="button" class="mode" disabled={$busy || !desktop} onclick={toggleApplyMode}>
          {$applyMode === "live" ? "Live (armed)" : "Preview"}
        </button>
        {#if !desktop}
          <span class="caption">Live apply requires the desktop shell.</span>
        {/if}
      </div>
      <p class="status" data-status={$status}>
        <span class="badge">{$status}</span>
        {$note}
      </p>
    </section>

    <section aria-labelledby="settings-startup">
      <h3 id="settings-startup">Startup</h3>
      {#if !desktop}
        <p class="caption">Run the desktop shell to manage autostart and background restore.</p>
      {:else}
        <div class="field-row">
          <label for="startup-toggle">Start with desktop session</label>
          <button
            id="startup-toggle"
            type="button"
            class="mode"
            disabled={$startup === null || (!$startup.available && !$startup.enabled)}
            onclick={() => runtimeService.setStartupEnabled(!$startup?.enabled)}
          >
            {$startup?.enabled ? "Enabled" : "Off"}
          </button>
        </div>
        <p class="caption">{$startup?.message ?? "Checking autostart status."}</p>
        <div class="field-row">
          <label for="background-toggle">Restore audio in background</label>
          <button
            id="background-toggle"
            type="button"
            class="mode"
            disabled={$backgroundStartup === null || (!$backgroundStartup.available && !$backgroundStartup.enabled)}
            onclick={() => runtimeService.setBackgroundStartupEnabled(!$backgroundStartup?.enabled)}
          >
            {$backgroundStartup?.enabled ? "Enabled" : "Off"}
          </button>
        </div>
        <p class="caption">{$backgroundStartup?.message ?? "Checking background restore status."}</p>
      {/if}
    </section>

    <section aria-labelledby="settings-updates">
      <h3 id="settings-updates">Updates</h3>
      <p class="caption">
        Loopwire is pre-release. Updates are delivered through your package manager or the project's release page; the
        app does not self-update.
      </p>
    </section>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgb(0 0 0 / 40%);
    z-index: 70;
  }

  .window {
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: min(460px, calc(100vw - 40px));
    max-height: min(560px, calc(100vh - 40px));
    display: flex;
    flex-direction: column;
    background: var(--lw-sidebar-bg);
    border: 1px solid var(--lw-hairline);
    border-radius: 10px;
    box-shadow: var(--lw-menu-shadow);
    z-index: 71;
  }

  .titlebar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 14px;
    border-bottom: 1px solid var(--lw-hairline);
  }

  h2 {
    font: var(--lw-text-column-header);
    margin: 0;
  }

  .close {
    border: none;
    background: transparent;
    color: var(--lw-text-secondary);
    font-size: 16px;
    cursor: pointer;
    padding: 2px 6px;
    border-radius: 4px;
  }

  .close:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }

  .content {
    overflow-y: auto;
    padding: 14px;
    display: flex;
    flex-direction: column;
    gap: var(--lw-space-5);
  }

  section {
    display: flex;
    flex-direction: column;
    gap: var(--lw-space-2);
  }

  h3 {
    font: var(--lw-text-card-title);
    margin: 0;
    color: var(--lw-text-primary);
  }

  .caption {
    font: var(--lw-text-subtitle);
    color: var(--lw-text-secondary);
    margin: 0;
  }

  .theme-picker {
    display: flex;
    gap: var(--lw-space-3);
  }

  .theme-tile {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    border: 1px solid var(--lw-hairline);
    border-radius: 8px;
    background: var(--lw-card-bg);
    color: var(--lw-text-primary);
    font: var(--lw-text-subtitle);
    padding: 8px;
    cursor: pointer;
    flex: 1;
  }

  .theme-tile[aria-checked="true"] {
    border-color: var(--lw-accent);
    box-shadow: 0 0 0 1px var(--lw-accent);
  }

  .theme-tile:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }

  .preview {
    width: 100%;
    height: 36px;
    border-radius: 5px;
    border: 1px solid var(--lw-hairline);
  }

  .preview.system {
    background: linear-gradient(110deg, #f2f3f4 50%, #1b1d1e 50%);
  }

  .preview.light {
    background: #f2f3f4;
  }

  .preview.dark {
    background: #1b1d1e;
  }

  .field-row {
    display: flex;
    align-items: center;
    gap: var(--lw-space-3);
  }

  .field-row label {
    font: var(--lw-text-body);
    color: var(--lw-text-primary);
    min-width: 150px;
  }

  select {
    flex: 1;
    background: var(--lw-card-bg);
    color: var(--lw-text-primary);
    border: 1px solid var(--lw-hairline);
    border-radius: 6px;
    padding: 4px 8px;
    font: var(--lw-text-body);
  }

  select:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }

  .mode {
    border: 1px solid var(--lw-hairline);
    border-radius: 6px;
    background: var(--lw-footer-button-bg);
    color: var(--lw-text-primary);
    font: var(--lw-text-body);
    padding: 4px 10px;
    cursor: pointer;
  }

  .mode:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .mode:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }

  .status {
    font: var(--lw-text-body);
    color: var(--lw-text-secondary);
    margin: 0;
    display: flex;
    align-items: baseline;
    gap: var(--lw-space-2);
  }

  .badge {
    font: var(--lw-text-pill);
    text-transform: uppercase;
    letter-spacing: 0.4px;
    color: var(--lw-accent);
    border: 1px solid currentColor;
    border-radius: 999px;
    padding: 2px 6px;
    flex: none;
  }

  .status[data-status="failed"] .badge,
  .status[data-status="rolled_back"] .badge {
    color: var(--lw-danger);
  }
</style>
