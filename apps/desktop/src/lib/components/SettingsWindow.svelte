<script lang="ts">
  import { tick } from "svelte";
  import { deviceStore, reapplySelectedDevice, runtimeService, themeService, hostCatalog, uiStore } from "../app";
  import { displayBackendName } from "../services/runtime";
  import { hasTauriRuntime } from "../services/statePersistence";
  import type { ThemeMode } from "../services/theme";

  interface Props {
    readonly onClose: () => void;
  }

  const { onClose }: Props = $props();

  const { mode: themeMode } = themeService;
  const {
    backendCandidates,
    capabilityReports,
    detectionNote,
    lastApplyMode,
    status,
    note,
    activity,
    busy,
    startup,
    backgroundStartup
  } = runtimeService;
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

  let exportJson = $state("");
  let importJson = $state("");

  function exportActiveDevice(): void {
    const deviceId = deviceStore.snapshot().activeConfigurationId;

    if (!deviceId) {
      uiStore.pushToast("error", "Select a device before exporting.");
      return;
    }

    const { result, json } = deviceStore.exportDevice(deviceId);

    if (!result.ok || !json) {
      uiStore.pushToast("error", result.ok ? "Export produced no JSON." : result.message);
      return;
    }

    exportJson = json;

    if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
      void navigator.clipboard.writeText(json).catch(() => undefined);
    }
  }

  function importDevice(): void {
    const { result } = deviceStore.importDevice(importJson);

    if (!result.ok) {
      uiStore.pushToast("error", result.message);
      return;
    }

    importJson = "";
    // The imported device becomes the selection, so the host must track it.
    reapplySelectedDevice();
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
        <span class="field-label">Host apply</span>
        <span class="caption">
          Automatic — selecting a device applies it through the saved backend when preflight passes; otherwise the
          switch runs in preview and reports why. Last transaction ran {$lastApplyMode === "live" ? "live" : "in preview"}.
        </span>
      </div>
      <p class="status" data-status={$status}>
        <span class="badge">{$status}</span>
        {$note}
      </p>
      {#if $activity.length > 0}
        <details class="ledger">
          <summary>Last runtime activity ({$activity.length} operations)</summary>
          <ul>
            {#each $activity as entry, index (index)}
              <li>
                <span class="op">{entry.operation}</span>
                <span class="op-message">{entry.message}</span>
              </li>
            {/each}
          </ul>
        </details>
      {/if}
      <details class="ledger" data-testid="diagnostics">
        <summary>Diagnostics ({$capabilityReports.length} capability {$capabilityReports.length === 1 ? "report" : "reports"})</summary>
        {#if $capabilityReports.length === 0}
          <p class="caption">
            No backend capability reports yet — run the desktop shell so host detection can probe PipeWire, PulseAudio,
            JACK, and ALSA.
          </p>
        {:else}
          {#each $capabilityReports as report (report.kind)}
            <div class="diagnostic-report">
              <p class="diagnostic-title">
                <strong>{report.displayName}</strong>
                <span class="badge">{report.availability}</span>
              </p>
              <p class="caption">Mixing: {report.mixing.controlScope}</p>
              <ul class="diagnostic-ops">
                {#each Object.entries(report.operations) as [operation, opState] (operation)}
                  <li><span class="op">{operation}</span><span class="op-message">{opState}</span></li>
                {/each}
              </ul>
              {#if report.diagnostics.length > 0}
                <ul>
                  {#each report.diagnostics as diagnostic, index (index)}
                    <li>
                      <span class="op">{diagnostic.level}</span>
                      <span class="op-message">{diagnostic.message}</span>
                    </li>
                  {/each}
                </ul>
              {/if}
            </div>
          {/each}
        {/if}
      </details>
    </section>

    <section aria-labelledby="settings-transfer">
      <h3 id="settings-transfer">Transfer</h3>
      <p class="caption">
        Export the selected device as versioned JSON (also copied to the clipboard when available), or paste an export
        to import it as a new device.
      </p>
      <div class="transfer-actions">
        <button type="button" class="mode" onclick={exportActiveDevice}>Export selected device</button>
      </div>
      {#if exportJson}
        <textarea
          class="transfer-text"
          readonly
          rows="6"
          aria-label="Exported device JSON"
          value={exportJson}
          onclick={(event) => event.currentTarget.select()}
        ></textarea>
      {/if}
      <textarea
        class="transfer-text"
        rows="4"
        aria-label="Device JSON to import"
        placeholder={'Paste a "loopwire.configuration" export here'}
        bind:value={importJson}
      ></textarea>
      <div class="transfer-actions">
        <button type="button" class="mode" disabled={!importJson.trim()} onclick={importDevice}>Import device</button>
      </div>
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

  .field-row label,
  .field-label {
    font: var(--lw-text-body);
    color: var(--lw-text-primary);
    min-width: 150px;
    flex: none;
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

  .ledger {
    font: var(--lw-text-subtitle);
    color: var(--lw-text-secondary);
  }

  .ledger summary {
    cursor: pointer;
  }

  .ledger ul {
    margin: 6px 0 0;
    padding-left: 16px;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .op {
    text-transform: capitalize;
    color: var(--lw-text-primary);
    margin-right: 6px;
  }

  .diagnostic-report {
    margin-top: 8px;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .diagnostic-title {
    margin: 0;
    display: flex;
    align-items: baseline;
    gap: var(--lw-space-2);
    color: var(--lw-text-primary);
  }

  .diagnostic-ops {
    margin: 0;
    padding-left: 16px;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .transfer-actions {
    display: flex;
    gap: var(--lw-space-2);
  }

  .transfer-text {
    width: 100%;
    resize: vertical;
    background: var(--lw-card-bg);
    color: var(--lw-text-primary);
    border: 1px solid var(--lw-hairline);
    border-radius: 6px;
    padding: 6px 8px;
    font: var(--lw-text-subtitle);
    font-family: monospace;
  }

  .transfer-text:focus-visible {
    outline: none;
    box-shadow: var(--lw-focus-ring);
  }
</style>
