<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { describeBackendChoiceCallout } from "./backend-choice";
  import { describeChromeModeSummary, type ChromeMode } from "./chrome-mode-summary";
  import { groupMonitorsByVisibility } from "./monitor-visibility";
  import { describeStartupRestoreSummary } from "./startup-restore-summary";
  import {
    describeConfigurationSwitchPreflight,
    describeLiveApplyPreflight,
    getNativeGainBlockerRoutes,
    type LiveApplyPreflight
  } from "./live-apply-preflight";
  import {
    describeSelectedRouteControlSemantics,
    routeGainEditingLockedForBackend,
    type RouteControlBackendCapability
  } from "./route-control-semantics";
  import {
    detectAudioBackends,
    enumerateInputSources,
    enumeratePlaybackDevices,
    type AudioBackendDetectionReport,
    type AudioInputSource,
    type AudioInputSourceReport,
    type AudioPlaybackDevice,
    type AudioPlaybackDeviceReport
  } from "@loopwire/audio-host/detectors";
  import {
    createJackGraphRuntimeAdapter,
    createPactlVirtualSinkRuntimeAdapter,
    createPipeWireGraphRuntimeAdapter,
    type CommandResult,
    type CommandRunner,
    type HostRuntimeConfiguration,
    type HostRuntimeOperationResult,
    type MissingStreamVerificationMode
  } from "@loopwire/audio-host/runtime";
  import {
    addInputSourceToConfiguration,
    addMonitorToConfiguration,
    addOutputBusToConfiguration,
    addRouteToConfiguration,
    applyBackendSelection,
    applyConfigurationSwitch,
    createConfigurationSwitchPlan,
    createConfiguration,
    createDefaultState,
    deleteConfiguration,
    duplicateConfiguration,
    exportConfiguration,
    getActiveConfiguration,
    importConfiguration,
    isMonitorHidden,
    removeInputSourceFromConfiguration,
    removeMonitorFromConfiguration,
    removeOutputBusFromConfiguration,
    removeRouteFromConfiguration,
    restoreState,
    selectBackend,
    serializeState,
    setEndpointDeviceName,
    setMonitorHidden,
    setRouteGain,
    setRouteMuted,
    setSelectedBackend,
    updateConfiguration,
    verifyStartupConfiguration,
    type AudioBackendKind,
    type AudioEndpoint,
    type AudioRoute,
    type BackendCandidate,
    type ConfigurationRuntimeAdapter,
    type ConfigurationRuntimePlan,
    type ConfigurationRuntimeResult,
    type LoopwireConfiguration,
    type LoopwireState,
    type RuntimeLogEntry,
    type RuntimeOperation,
    type RuntimeTransactionReason
  } from "@loopwire/core";

  type HostApplyMode = "preview" | "live";
  type RuntimeBadge = "ready" | "applying" | "verified" | "rolled_back" | "failed";
  type SourceCandidate = {
    readonly id: string;
    readonly category: string;
    readonly label: string;
    readonly detail: string;
    readonly channels: number;
    readonly deviceName?: string;
  };
  type OutputCandidate = {
    readonly id: string;
    readonly category: string;
    readonly label: string;
    readonly detail: string;
    readonly channels: number;
    readonly deviceName?: string;
  };
  type MonitorCandidate = {
    readonly id: string;
    readonly label: string;
    readonly detail: string;
    readonly channels: number;
  };
  type StartupStatus = {
    readonly enabled: boolean;
    readonly available: boolean;
    readonly path: string;
    readonly binary: string;
    readonly message: string;
  };
  type RoutingCable = {
    readonly id: string;
    readonly d: string;
    readonly label: string;
    readonly muted: boolean;
  };
  type RoutingBoardModel = {
    readonly cables: readonly RoutingCable[];
    readonly height: number;
    readonly routeCount: number;
    readonly mutedCount: number;
  };
  const storageKey = "loopwire.state.v1";
  const chromeStorageKey = "loopwire.chrome.v1";
  const routingBoardTop = 150;
  const routingBoardRowGap = 136;
  const routingBoardBottom = 80;
  const fallbackBackendCandidates: BackendCandidate[] = [
    {
      kind: "pipewire",
      displayName: "PipeWire",
      availability: "available",
      priority: 10
    },
    {
      kind: "pulseaudio",
      displayName: "PulseAudio",
      availability: "available",
      priority: 20
    },
    {
      kind: "jack",
      displayName: "JACK",
      availability: "unavailable",
      priority: 30,
      reason: "JACK bridge not detected"
    },
    {
      kind: "alsa",
      displayName: "ALSA",
      availability: "unavailable",
      priority: 40,
      reason: "Direct ALSA fallback is not enabled"
    }
  ];
  const browserMonitorTargetDevices: readonly AudioPlaybackDevice[] = [
    {
      backend: "pulseaudio",
      deviceName: "alsa_output.usb_studio_headphones.analog-stereo",
      label: "Studio Headphones",
      detail: "Browser preview sample"
    },
    {
      backend: "pulseaudio",
      deviceName: "alsa_output.pci_room_speakers.analog-stereo",
      label: "Room Speakers",
      detail: "Browser preview sample"
    }
  ];

  const browserInputSourceCandidates: readonly SourceCandidate[] = [
    {
      id: "browser",
      category: "Running apps",
      label: "Browser",
      detail: "Sample PulseAudio stream",
      channels: 2,
      deviceName: "browser"
    },
    {
      id: "meeting-app",
      category: "Running apps",
      label: "Meeting App",
      detail: "Sample communication stream",
      channels: 2,
      deviceName: "meeting-app"
    }
  ];
  const staticSourceCandidates: readonly SourceCandidate[] = [
    { id: "browser", category: "Running apps", label: "Browser", detail: "Application stream", channels: 2 },
    { id: "meeting-app", category: "Running apps", label: "Meeting App", detail: "Communication stream", channels: 2 },
    { id: "system", category: "Special sources", label: "System Sounds", detail: "Desktop events", channels: 2 },
    { id: "mic", category: "Audio devices", label: "Studio Microphone", detail: "Hardware input", channels: 2 }
  ];
  const appOutputCandidates: readonly OutputCandidate[] = [
    {
      id: "recorder",
      category: "Virtual buses",
      label: "Recorder Bus",
      detail: "Recording and DAW capture",
      channels: 2
    },
    {
      id: "broadcast",
      category: "Virtual buses",
      label: "Broadcast Bus",
      detail: "Streaming and production output",
      channels: 2
    },
    {
      id: "archive",
      category: "Virtual buses",
      label: "Archive Bus",
      detail: "Local recording safety mix",
      channels: 2
    },
    {
      id: "meeting",
      category: "Virtual buses",
      label: "Meeting App",
      detail: "Communication app return path",
      channels: 2
    }
  ];
  const monitorCandidates: readonly MonitorCandidate[] = [
    { id: "headphones", label: "Headphones", detail: "Primary operator monitor", channels: 2 },
    { id: "meters", label: "Meter Bridge", detail: "Visual metering output", channels: 2 },
    { id: "producer", label: "Producer Monitor", detail: "Producer foldback mix", channels: 2 },
    { id: "speakers", label: "Speakers", detail: "Room playback monitor", channels: 2 }
  ];

  const appRuntimeAdapter: ConfigurationRuntimeAdapter = {
    unload: (configuration) => ({
      ok: true,
      message: `Preview-unloaded ${configuration.name}.`
    }),
    apply: (configuration) => ({
      ok: true,
      message: `Preview-staged ${configuration.name}.`
    }),
    verify: (configuration) => ({
      ok: true,
      message: `Preview-verified ${configuration.name}.`
    }),
    rollback: (configuration) => ({
      ok: true,
      message: `Preview-restored ${configuration.name}.`
    })
  };

  let state: LoopwireState = createDefaultState();
  let chromeMode: ChromeMode = "native";
  let hostApplyMode: HostApplyMode = "preview";
  let restoreNote = "";
  let runtimeStatus: RuntimeBadge = "ready";
  let runtimeNote = "Preview runtime ready.";
  let runtimeActivity: readonly RuntimeLogEntry[] = [];
  let runtimeActivityReason: RuntimeTransactionReason | undefined;
  let configurationSwitchBusy = false;
  let configurationSwitchToken = 0;
  let backendCandidates: readonly BackendCandidate[] = fallbackBackendCandidates;
  let backendCapabilityReports: readonly RouteControlBackendCapability[] = [];
  let backendDetectionNote = "Browser preview uses packaged backend candidates.";
  let monitorTargetDevices: readonly AudioPlaybackDevice[] = [];
  let monitorTargetNote = "Choose a backend to list host monitor sinks.";
  let detectedSourceCandidates: readonly SourceCandidate[] = [];
  let sourcePickerCandidates: readonly SourceCandidate[] = staticSourceCandidates;
  let outputPickerCandidates: readonly OutputCandidate[] = appOutputCandidates;
  let sourcePickerNote = "Choose a backend to list running app streams.";
  let sourcePanelOpen = false;
  let outputPanelOpen = false;
  let monitorPanelOpen = false;
  let transferOpen = false;
  let diagnosticsOpen = false;
  let routeSourceId = "";
  let routeOutputId = "";
  let startupEnabled = false;
  let startupAvailable = true;
  let startupBusy = false;
  let startupPath = "";
  let startupBinary = "";
  let startupNote = "Desktop shell can check user autostart status.";
  let backgroundStartupEnabled = false;
  let backgroundStartupAvailable = true;
  let backgroundStartupBusy = false;
  let backgroundStartupPath = "";
  let backgroundStartupBinary = "";
  let backgroundStartupNote = "Desktop shell can check user background restore status.";
  let transferText = "";
  let transferNote = "Export the active configuration or paste a Loopwire configuration JSON payload.";

  onMount(() => {
    restoreChromePreference();
    void bootApplication();
  });

  $: activeConfiguration = getActiveConfiguration(state);
  $: monitorVisibilityGroups = groupMonitorsByVisibility(state, activeConfiguration);
  $: visibleMonitors = monitorVisibilityGroups.visible;
  $: hiddenMonitors = monitorVisibilityGroups.hidden;
  $: hiddenMonitorCount = hiddenMonitors.length;
  $: backendDecision = selectBackend(backendCandidates, state.selectedBackend);
  $: selectedBackend = state.selectedBackend ?? "";
  $: selectedBackendName = state.selectedBackend ? displayBackendName(state.selectedBackend) : "None selected";
  $: startupRestoreSummary = describeStartupRestoreSummary({
    configuration: activeConfiguration,
    selectedBackendName,
    enabled: backgroundStartupEnabled,
    available: backgroundStartupAvailable
  });
  $: chromeModeSummary = describeChromeModeSummary({ mode: chromeMode, desktopRuntimeAvailable });
  $: backendSelectionSummary = describeBackendSelectionSummary();
  $: backendChoiceCallout = describeBackendChoiceCallout(backendDecision, selectedBackendName);
  $: selectedBackendCapability = backendCapabilityFor(state.selectedBackend);
  $: routeControlSemantics = describeSelectedRouteControlSemantics(
    state.selectedBackend,
    backendDecision.mode,
    selectedBackendCapability
  );
  $: routingBoard = buildRoutingBoard(activeConfiguration.inputs, activeConfiguration.outputs, activeConfiguration.routes);
  $: liveApplyPreflight = describeLiveApplyPreflight(
    activeConfiguration,
    state.selectedBackend,
    displayBackendName,
    selectedBackendCapability
  );
  $: nativeGainBlockerRoutes = getNativeGainBlockerRoutes(
    activeConfiguration,
    state.selectedBackend,
    selectedBackendCapability
  );
  $: canResetNativeRouteGains = nativeGainBlockerRoutes.length > 0;
  $: routeGainEditingLocked = routeGainEditingLockedForBackend(state.selectedBackend, selectedBackendCapability);
  $: desktopRuntimeAvailable = hasTauriRuntime();
  $: startupActionDisabled = startupBusy || !desktopRuntimeAvailable || (!startupAvailable && !startupEnabled);
  $: backgroundStartupActionDisabled =
    backgroundStartupBusy || !desktopRuntimeAvailable || (!backgroundStartupAvailable && !backgroundStartupEnabled);
  $: sourcePickerCandidates = detectedSourceCandidates.length > 0 ? detectedSourceCandidates : staticSourceCandidates;
  $: outputPickerCandidates = nativeBackendUsesHostTargets(state.selectedBackend)
    ? [...monitorTargetDevices.map(toHostOutputCandidate), ...appOutputCandidates]
    : appOutputCandidates;
  $: if (!activeConfiguration.inputs.some((endpoint) => endpoint.id === routeSourceId)) {
    routeSourceId = activeConfiguration.inputs[0]?.id ?? "";
  }
  $: if (!activeConfiguration.outputs.some((endpoint) => endpoint.id === routeOutputId)) {
    routeOutputId = activeConfiguration.outputs[0]?.id ?? "";
  }
  $: selectedRouteExists = activeConfiguration.routes.some(
    (route) => route.from === routeSourceId && route.to === routeOutputId
  );
  $: canAddSelectedRoute = Boolean(routeSourceId && routeOutputId && !selectedRouteExists);

  async function bootApplication(): Promise<void> {
    await restorePersistedState();
    await initializeRuntimeState();
  }

  function restoreChromePreference(): void {
    chromeMode = parseChromeMode(localStorage.getItem(chromeStorageKey));
    void applyWindowChrome(chromeMode, { quiet: true });
  }

  function parseChromeMode(value: string | null): ChromeMode {
    return value === "custom" ? "custom" : "native";
  }

  async function setChromeMode(nextMode: ChromeMode): Promise<void> {
    chromeMode = nextMode;
    localStorage.setItem(chromeStorageKey, nextMode);
    await applyWindowChrome(nextMode);
  }

  async function applyWindowChrome(mode: ChromeMode, options: { readonly quiet?: boolean } = {}): Promise<void> {
    if (!hasTauriRuntime()) {
      if (!options.quiet && mode === "custom") {
        runtimeStatus = "verified";
        runtimeNote = "Custom chrome is shown in browser preview; decoration switching runs in the desktop shell.";
      }

      return;
    }

    try {
      await getCurrentWindow().setDecorations(mode === "native");

      if (!options.quiet) {
        runtimeStatus = "verified";
        runtimeNote = mode === "custom"
          ? "Custom chrome is controlling the undecorated desktop window."
          : "Native window chrome restored.";
      }
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not update window chrome.";
    }
  }

  async function restorePersistedState(): Promise<void> {
    const browserRaw = localStorage.getItem(storageKey);

    if (!hasTauriRuntime()) {
      const restored = restoreState(browserRaw, state);
      state = restored.state;
      restoreNote = restored.ok ? "Restored" : "Ready";
      return;
    }

    try {
      const desktopRaw = await invoke<string>("read_state");
      const restored = restoreState(desktopRaw || browserRaw, state);
      state = restored.state;
      restoreNote = restored.ok ? "Restored" : "Ready";
      localStorage.setItem(storageKey, serializeState(state));

      if (!desktopRaw && restored.ok) {
        void persistDesktopState(serializeState(state));
      }
    } catch (error) {
      const restored = restoreState(browserRaw, state);
      state = restored.state;
      restoreNote = restored.ok ? "Restored from browser fallback" : "Ready";
      startupNote = error instanceof Error ? error.message : "Could not read desktop state file.";
    }
  }

  function applyState(next: LoopwireState): void {
    state = next;
    const serialized = serializeState(next);
    localStorage.setItem(storageKey, serialized);
    void persistDesktopState(serialized);
  }

  async function persistDesktopState(raw: string): Promise<void> {
    if (!hasTauriRuntime()) {
      return;
    }

    try {
      await invoke<string>("write_state", { raw });
    } catch (error) {
      restoreNote = error instanceof Error ? "State file write failed" : "State file unavailable";
    }
  }

  async function initializeRuntimeState(): Promise<void> {
    await refreshStartupStatus();
    await refreshBackendDetection();
    await refreshMonitorTargetDevices();
    await refreshSourceCandidates();
    await verifyStartupState();
  }

  async function refreshStartupStatus(): Promise<void> {
    if (!hasTauriRuntime()) {
      startupEnabled = false;
      startupAvailable = true;
      startupPath = "~/.config/autostart/loopwire.desktop";
      startupBinary = "";
      startupNote = "Run the desktop shell to manage user-scoped XDG autostart.";
      backgroundStartupEnabled = false;
      backgroundStartupAvailable = true;
      backgroundStartupPath = "~/.config/systemd/user/loopwire.service";
      backgroundStartupBinary = "";
      backgroundStartupNote = "Run the desktop shell to manage user-scoped background restore.";
      return;
    }

    await runStartupAction("status");
    await runBackgroundStartupAction("background_status");
  }

  async function refreshBackendDetection(): Promise<void> {
    if (!hasTauriRuntime()) {
      backendCandidates = fallbackBackendCandidates;
      backendCapabilityReports = [];
      backendDetectionNote = "Browser preview uses packaged backend candidates; run the desktop shell for host detection.";
      return;
    }

    backendDetectionNote = "Detecting Linux audio backends.";

    try {
      const report = await detectAudioBackends(createTauriCommandRunner(), new Date(), "linux");
      backendCandidates = report.candidates;
      backendCapabilityReports = report.reports;
      backendDetectionNote = describeBackendDetection(report);
      selectOnlyAvailableBackend(report.candidates);
    } catch (error) {
      backendCandidates = fallbackBackendCandidates;
      backendCapabilityReports = [];
      backendDetectionNote = error instanceof Error ? `Backend detection failed: ${error.message}` : "Backend detection failed.";
    }
  }

  async function refreshMonitorTargetDevices(backend: AudioBackendKind | undefined = state.selectedBackend): Promise<void> {
    if (!backend) {
      monitorTargetDevices = [];
      monitorTargetNote = "Choose an audio backend before selecting physical monitor sinks.";
      return;
    }

    if (!hasTauriRuntime()) {
      monitorTargetDevices = backend === "pulseaudio" ? browserMonitorTargetDevices : [];
      monitorTargetNote =
        backend === "pulseaudio"
          ? "Browser preview shows sample PulseAudio sinks; the desktop shell lists real host sinks."
          : `${displayBackendName(backend)} monitor targets use manual names in browser preview; the desktop shell lists real ports.`;
      return;
    }

    monitorTargetNote = describeMonitorTargetListing(backend);

    try {
      const report = await enumeratePlaybackDevices(createTauriCommandRunner(), backend, new Date());
      monitorTargetDevices = report.devices;
      monitorTargetNote = describePlaybackDeviceReport(report);
    } catch (error) {
      monitorTargetDevices = [];
      monitorTargetNote = error instanceof Error ? `Could not list monitor targets: ${error.message}` : "Could not list monitor targets.";
    }
  }

  async function refreshSourceCandidates(backend: AudioBackendKind | undefined = state.selectedBackend): Promise<void> {
    if (!backend) {
      detectedSourceCandidates = [];
      sourcePickerNote = "Choose an audio backend before listing running app streams.";
      return;
    }

    if (!hasTauriRuntime()) {
      detectedSourceCandidates = backend === "pulseaudio" ? browserInputSourceCandidates : [];
      sourcePickerNote =
        backend === "pulseaudio"
          ? "Browser preview shows sample PulseAudio streams; the desktop shell lists real running apps."
          : `${displayBackendName(backend)} source selection uses static candidates in browser preview; the desktop shell lists real ports.`;
      return;
    }

    sourcePickerNote = describeSourceListing(backend);

    try {
      const report = await enumerateInputSources(createTauriCommandRunner(), backend, new Date());
      detectedSourceCandidates = report.sources.map(toSourceCandidate);
      sourcePickerNote = describeInputSourceReport(report);
    } catch (error) {
      detectedSourceCandidates = [];
      sourcePickerNote = error instanceof Error ? `Could not list input sources: ${error.message}` : "Could not list input sources.";
    }
  }

  async function setStartupEnabled(enabled: boolean): Promise<void> {
    await runStartupAction(enabled ? "install" : "uninstall");
  }

  async function setBackgroundStartupEnabled(enabled: boolean): Promise<void> {
    await runBackgroundStartupAction(enabled ? "background_install" : "background_uninstall");
  }

  async function runStartupAction(action: "status" | "install" | "uninstall"): Promise<void> {
    startupBusy = true;

    try {
      const raw = await invoke<string>("manage_startup", { action });
      const status = parseStartupStatus(raw);
      startupEnabled = status.enabled;
      startupAvailable = status.available;
      startupPath = status.path;
      startupBinary = status.binary;
      startupNote = status.message;
      runtimeStatus = status.available ? "verified" : "failed";
      runtimeNote = describeStartupRuntimeNote(status, "desktop");
    } catch (error) {
      startupAvailable = false;
      startupNote = error instanceof Error ? error.message : "Could not manage desktop autostart.";
      runtimeStatus = "failed";
      runtimeNote = startupNote;
    } finally {
      startupBusy = false;
    }
  }

  async function runBackgroundStartupAction(
    action: "background_status" | "background_install" | "background_uninstall"
  ): Promise<void> {
    backgroundStartupBusy = true;

    try {
      const raw = await invoke<string>("manage_startup", { action });
      const status = parseStartupStatus(raw);
      backgroundStartupEnabled = status.enabled;
      backgroundStartupAvailable = status.available;
      backgroundStartupPath = status.path;
      backgroundStartupBinary = status.binary;
      backgroundStartupNote = status.message;
      runtimeStatus = status.available ? "verified" : "failed";
      runtimeNote = describeStartupRuntimeNote(status, "background");
    } catch (error) {
      backgroundStartupAvailable = false;
      backgroundStartupNote = error instanceof Error ? error.message : "Could not manage background restore.";
      runtimeStatus = "failed";
      runtimeNote = backgroundStartupNote;
    } finally {
      backgroundStartupBusy = false;
    }
  }

  function selectOnlyAvailableBackend(candidates: readonly BackendCandidate[]): void {
    const decision = selectBackend(candidates, state.selectedBackend);

    if (decision.mode === "auto" && decision.backend.kind !== state.selectedBackend) {
      applyState(setSelectedBackend(state, decision.backend.kind));
    }
  }

  async function chooseConfiguration(configurationId: string, sourceState: LoopwireState = state): Promise<ConfigurationRuntimeResult> {
    const switchToken = ++configurationSwitchToken;
    configurationSwitchBusy = true;
    const targetConfiguration = sourceState.configurations.find((configuration) => configuration.id === configurationId);

    if (!targetConfiguration) {
      const reason = `Unknown configuration: ${configurationId}`;
      if (isCurrentConfigurationSwitch(switchToken)) {
        runtimeStatus = "failed";
        runtimeNote = reason;
        configurationSwitchBusy = false;
      }

      return {
        ok: false,
        status: "failed",
        state: sourceState,
        plan: {
          id: `switch-missing-${configurationId}-${new Date().toISOString()}`,
          reason: "switch",
          toConfigurationId: configurationId,
          operations: [],
          createdAt: new Date().toISOString()
        },
        log: [],
        reason
      };
    }

    const preflight = describeConfigurationSwitchPreflight(
      targetConfiguration,
      sourceState.selectedBackend,
      backendCapabilityReports,
      displayBackendName
    );

    if (hostApplyMode === "live" && !preflight.ok) {
      if (isCurrentConfigurationSwitch(switchToken)) {
        runtimeStatus = "failed";
        runtimeNote = preflight.message;
        configurationSwitchBusy = false;
      }

      return {
        ok: false,
        status: "failed",
        state: sourceState,
        plan: createConfigurationSwitchPlan(sourceState, configurationId, new Date().toISOString()),
        log: [],
        reason: preflight.message
      };
    }

    let result: ConfigurationRuntimeResult;

    try {
      result = await executeConfigurationSwitch(sourceState, configurationId);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "Configuration switch failed.";
      result = {
        ok: false,
        status: "failed",
        state: sourceState,
        plan: createConfigurationSwitchPlan(sourceState, configurationId, new Date().toISOString()),
        log: [],
        reason
      };
    }

    if (isCurrentConfigurationSwitch(switchToken)) {
      if (result.ok) {
        applyState(result.state);
      }

      updateRuntimeStatus(result);
      configurationSwitchBusy = false;
    }

    return result;
  }

  function isCurrentConfigurationSwitch(switchToken: number): boolean {
    return switchToken === configurationSwitchToken;
  }

  async function chooseBackend(kind: AudioBackendKind): Promise<void> {
    const previousMode = hostApplyMode;

    if (previousMode === "live") {
      hostApplyMode = "preview";
    }

    runtimeStatus = "applying";
    runtimeNote = `Verifying ${displayBackendName(kind)} with ${activeConfiguration.name}.`;

    const result = await applyBackendSelection(
      state,
      kind,
      createRuntimeAdapterForBackend(kind, "preview"),
      new Date().toISOString()
    );

    if (result.ok) {
      applyState(result.state);
      await Promise.all([refreshMonitorTargetDevices(kind), refreshSourceCandidates(kind)]);
    }

    updateRuntimeStatus(result);

    if (previousMode === "live") {
      const disarmNote = `${displayBackendName(kind)} selected; live host apply was disarmed for preview verification.`;
      runtimeStatus = result.ok ? "ready" : "failed";
      runtimeNote = result.ok ? `${disarmNote} ${describeRuntimeSuccess(result)}` : `${disarmNote} ${result.reason}`;
    }
  }

  function handleBackendChange(event: Event): void {
    const value = (event.currentTarget as HTMLSelectElement).value;

    if (!value) {
      return;
    }

    void chooseBackend(value as AudioBackendKind);
  }

  function toggleHostApplyMode(): void {
    if (hostApplyMode === "preview" && !state.selectedBackend) {
      runtimeStatus = "failed";
      runtimeNote = "Choose a detected backend before arming live host apply.";
      return;
    }

    if (hostApplyMode === "preview" && !liveApplyPreflight.ok) {
      runtimeStatus = "failed";
      runtimeNote = liveApplyPreflight.message;
      return;
    }

    hostApplyMode = hostApplyMode === "preview" ? "live" : "preview";
    runtimeStatus = "ready";
    runtimeNote = hostApplyMode === "live" ? "Live host apply armed for the next switch." : "Preview runtime ready.";
  }

  function toggleMonitor(monitorId: string): void {
    applyState(setMonitorHidden(state, activeConfiguration.id, monitorId, !isMonitorHidden(state, activeConfiguration, monitorId)));
  }

  function addSourceToActiveConfiguration(source: SourceCandidate): void {
    try {
      const output = preferredOutputForNewSource();
      const updated = addInputSourceToConfiguration(
        state,
        activeConfiguration.id,
        {
          id: source.id,
          label: source.label,
          channels: source.channels,
          ...(output ? { routeToOutputId: output.id } : {}),
          ...(source.deviceName ? { deviceName: source.deviceName } : {})
        },
        new Date().toISOString()
      );
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote = output
        ? `Added ${source.label} and routed it to ${output.label}.`
        : `Added ${source.label}.`;
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not add source.";
    }
  }

  function addOutputToActiveConfiguration(output: OutputCandidate): void {
    try {
      const updated = addOutputBusToConfiguration(
        state,
        activeConfiguration.id,
        {
          id: output.id,
          label: output.label,
          channels: output.channels,
          ...(output.deviceName ? { deviceName: output.deviceName } : {}),
          ...(output.deviceName && nativeBackendUsesHostTargets(state.selectedBackend)
            ? { routeExistingInputs: "host-device" as const }
            : {})
        },
        new Date().toISOString()
      );
      const addedRouteCount = updated.configuration.routes.length - activeConfiguration.routes.length;
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote =
        addedRouteCount > 0
          ? `Added ${output.label} and routed ${addedRouteCount} sources to it.`
          : `Added ${output.label}.`;
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not add output.";
    }
  }

  function addMonitorToActiveConfiguration(monitor: MonitorCandidate): void {
    try {
      const updated = addMonitorToConfiguration(
        state,
        activeConfiguration.id,
        {
          id: monitor.id,
          label: monitor.label,
          channels: monitor.channels
        },
        new Date().toISOString()
      );
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote = `Added ${monitor.label} as a monitor.`;
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not add monitor.";
    }
  }

  function removeSourceFromActiveConfiguration(endpoint: AudioEndpoint): void {
    try {
      const removedRouteCount = activeConfiguration.routes.filter((route) => route.from === endpoint.id).length;
      const updated = removeInputSourceFromConfiguration(state, activeConfiguration.id, endpoint.id, new Date().toISOString());
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote =
        removedRouteCount > 0
          ? `Removed ${endpoint.label} and ${removedRouteCount} routes.`
          : `Removed ${endpoint.label}.`;
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not remove source.";
    }
  }

  function removeOutputFromActiveConfiguration(endpoint: AudioEndpoint): void {
    try {
      const removedRouteCount = activeConfiguration.routes.filter((route) => route.to === endpoint.id).length;
      const updated = removeOutputBusFromConfiguration(state, activeConfiguration.id, endpoint.id, new Date().toISOString());
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote =
        removedRouteCount > 0
          ? `Removed ${endpoint.label} and ${removedRouteCount} routes.`
          : `Removed ${endpoint.label}.`;
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not remove output.";
    }
  }

  function removeMonitorFromActiveConfiguration(endpoint: AudioEndpoint): void {
    try {
      const updated = removeMonitorFromConfiguration(state, activeConfiguration.id, endpoint.id, new Date().toISOString());
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote = `Removed ${endpoint.label}.`;
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not remove monitor.";
    }
  }

  function sourceAlreadyAdded(source: SourceCandidate): boolean {
    return activeConfiguration.inputs.some(
      (input) => input.id === source.id || input.label.toLowerCase() === source.label.toLowerCase()
    );
  }

  function outputAlreadyAdded(output: OutputCandidate): boolean {
    return activeConfiguration.outputs.some(
      (candidate) =>
        candidate.id === output.id ||
        candidate.label.toLowerCase() === output.label.toLowerCase() ||
        (Boolean(output.deviceName) && candidate.deviceName === output.deviceName)
    );
  }

  function monitorAlreadyAdded(monitor: MonitorCandidate): boolean {
    return activeConfiguration.monitors.some(
      (candidate) => candidate.id === monitor.id || candidate.label.toLowerCase() === monitor.label.toLowerCase()
    );
  }

  function preferredOutputForNewSource(): AudioEndpoint | undefined {
    if (nativeBackendUsesHostTargets(state.selectedBackend)) {
      const hostOutput = activeConfiguration.outputs.find((output) => Boolean(output.deviceName?.trim()));

      if (hostOutput) {
        return hostOutput;
      }
    }

    return activeConfiguration.outputs[0];
  }

  function handleEndpointDeviceName(endpointId: string, event: Event): void {
    const deviceName = (event.currentTarget as HTMLInputElement).value.trim();
    updateEndpointDeviceName(endpointId, deviceName);
  }

  function handleMonitorTargetSelection(monitorId: string, event: Event): void {
    const deviceName = (event.currentTarget as HTMLSelectElement).value;
    updateEndpointDeviceName(monitorId, deviceName);
  }

  function updateEndpointDeviceName(endpointId: string, deviceName: string): void {
    const updated = setEndpointDeviceName(state, activeConfiguration.id, endpointId, deviceName, new Date().toISOString());

    applyState(updated.state);
    runtimeStatus = "verified";
    runtimeNote = deviceName
      ? `Saved ${deviceName} as the host binding for ${describeEndpoint(endpointId)}.`
      : `Cleared the host binding for ${describeEndpoint(endpointId)}.`;
  }

  function addSelectedRouteToActiveConfiguration(): void {
    try {
      const updated = addRouteToConfiguration(
        state,
        activeConfiguration.id,
        {
          from: routeSourceId,
          to: routeOutputId
        },
        new Date().toISOString()
      );
      const route = updated.configuration.routes.at(-1);
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote = route ? `Added route ${describeRouteLabel(updated.configuration, route)}.` : "Added route.";
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not add route.";
    }
  }

  function removeRouteFromActiveConfiguration(route: AudioRoute): void {
    try {
      const routeLabel = describeRoute(route.id);
      const updated = removeRouteFromConfiguration(state, activeConfiguration.id, route.id, new Date().toISOString());
      applyState(updated.state);
      runtimeStatus = "verified";
      runtimeNote = `Removed route ${routeLabel}.`;
    } catch (error) {
      runtimeStatus = "failed";
      runtimeNote = error instanceof Error ? error.message : "Could not remove route.";
    }
  }

  function handleRouteGain(routeId: string, event: Event): void {
    if (routeGainEditingLocked) {
      runtimeStatus = "failed";
      runtimeNote = routeGainLockRuntimeNote();
      return;
    }

    const gain = Number((event.currentTarget as HTMLInputElement).value) / 100;
    const updated = setRouteGain(state, activeConfiguration.id, routeId, gain, new Date().toISOString());
    applyState(updated.state);
    runtimeStatus = "verified";
    runtimeNote = `Saved ${Math.round(gain * 100)}% gain for ${describeRoute(routeId)} in the app runtime.`;
  }

  function toggleRouteMuted(routeId: string): void {
    const route = activeConfiguration.routes.find((candidate) => candidate.id === routeId);

    if (!route) {
      runtimeStatus = "failed";
      runtimeNote = `Unknown route: ${routeId}`;
      return;
    }

    const updated = setRouteMuted(state, activeConfiguration.id, routeId, !route.muted, new Date().toISOString());
    applyState(updated.state);
    runtimeStatus = "verified";
    runtimeNote = `${describeRoute(routeId)} is ${route.muted ? "active" : "muted"} in the app runtime.`;
  }

  function resetNativeRouteGains(): void {
    if (nativeGainBlockerRoutes.length === 0 || !state.selectedBackend) {
      return;
    }

    const updatedAt = new Date().toISOString();
    let nextState = state;

    for (const route of nativeGainBlockerRoutes) {
      nextState = setRouteGain(nextState, activeConfiguration.id, route.id, 1, updatedAt).state;
    }

    applyState(nextState);
    runtimeStatus = "verified";
    const route = nativeGainBlockerRoutes[0];
    runtimeNote =
      nativeGainBlockerRoutes.length === 1 && route
        ? `Reset ${describeRouteLabel(activeConfiguration, route)} to 100% for live apply.`
        : `Reset ${nativeGainBlockerRoutes.length} route gains to 100% for ${displayBackendName(state.selectedBackend)} live apply.`;
  }

  async function minimizeWindow(): Promise<void> {
    await runWindowAction("minimize");
  }

  async function toggleWindowMaximize(): Promise<void> {
    await runWindowAction("toggleMaximize");
  }

  async function closeWindow(): Promise<void> {
    await runWindowAction("close");
  }

  async function runWindowAction(action: "minimize" | "toggleMaximize" | "close"): Promise<void> {
    if (!hasTauriRuntime()) {
      runtimeStatus = "failed";
      runtimeNote = "Window controls are available in the Tauri desktop shell.";
      return;
    }

    try {
      const currentWindow = getCurrentWindow();
      await currentWindow[action]();
    } catch {
      runtimeStatus = "failed";
      runtimeNote = "Window controls are available in the Tauri desktop shell.";
    }
  }

  async function verifyStartupState(): Promise<void> {
    runtimeStatus = "applying";
    runtimeNote = "Verifying the selected configuration in preview mode.";

    const result = await verifyStartupConfiguration(
      state,
      createSelectedRuntimeAdapter("preview"),
      new Date().toISOString()
    );

    if (result.ok) {
      applyState(result.state);
    }

    updateRuntimeStatus(result);
  }

  async function executeConfigurationSwitch(
    sourceState: LoopwireState,
    configurationId: string
  ): Promise<ConfigurationRuntimeResult> {
    runtimeStatus = "applying";
    runtimeNote = hostApplyMode === "live" ? "Switching with live host apply armed." : "Switching in preview mode.";
    return applyConfigurationSwitch(
      sourceState,
      configurationId,
      createSelectedRuntimeAdapter(hostApplyMode),
      new Date().toISOString()
    );
  }

  function createRuntimeAdapterForBackend(
    backend: AudioBackendKind | undefined,
    mode: HostApplyMode
  ): ConfigurationRuntimeAdapter {
    if (!backend) {
      return appRuntimeAdapter;
    }

    return {
      unload: (configuration, plan) => runSelectedHostRuntimeOperation(backend, "unload", configuration, plan, mode),
      apply: (configuration, plan) => runSelectedHostRuntimeOperation(backend, "apply", configuration, plan, mode),
      verify: (configuration, plan) => runSelectedHostRuntimeOperation(backend, "verify", configuration, plan, mode),
      rollback: (configuration, plan) => runSelectedHostRuntimeOperation(backend, "rollback", configuration, plan, mode)
    };
  }

  function createSelectedRuntimeAdapter(mode: HostApplyMode): ConfigurationRuntimeAdapter {
    return createRuntimeAdapterForBackend(state.selectedBackend, mode);
  }

  function createHostRuntimeAdapter(
    backend: AudioBackendKind,
    mode: HostApplyMode,
    reason: RuntimeTransactionReason
  ): ConfigurationRuntimeAdapter | undefined {
    const runner = mode === "live" ? createTauriCommandRunner() : createUnavailableCommandRunner();
    const hostMode = mode === "live" ? "apply" : "dry-run";

    if (backend === "pipewire") {
      const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: hostMode });
      return hostAdapterFromOperations(adapter);
    }

    if (backend === "pulseaudio") {
      const missingStreamVerification: MissingStreamVerificationMode = reason === "startup" ? "pending" : "fail";
      const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: hostMode, missingStreamVerification });
      return hostAdapterFromOperations(adapter);
    }

    if (backend === "jack") {
      const adapter = createJackGraphRuntimeAdapter(runner, { mode: hostMode });
      return hostAdapterFromOperations(adapter);
    }

    return undefined;
  }

  async function runSelectedHostRuntimeOperation(
    backend: AudioBackendKind,
    operationName: RuntimeOperation,
    configuration: Parameters<ConfigurationRuntimeAdapter["apply"]>[0],
    plan: ConfigurationRuntimePlan,
    mode: HostApplyMode
  ): Promise<HostRuntimeOperationResult> {
    const hostAdapter = createHostRuntimeAdapter(backend, mode, plan.reason);

    if (!hostAdapter) {
      return appRuntimeAdapter[operationName](configuration, plan);
    }

    return runHostRuntimeOperation(hostAdapter[operationName], configuration, plan, mode);
  }

  function hostAdapterFromOperations(adapter: {
    unload(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
    apply(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
    verify(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
    rollback(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  }): ConfigurationRuntimeAdapter {
    return {
      unload: (configuration) => adapter.unload(toHostRuntimeConfiguration(configuration)),
      apply: (configuration) => adapter.apply(toHostRuntimeConfiguration(configuration)),
      verify: (configuration) => adapter.verify(toHostRuntimeConfiguration(configuration)),
      rollback: (configuration) => adapter.rollback(toHostRuntimeConfiguration(configuration))
    };
  }

  async function runHostRuntimeOperation(
    operation: ConfigurationRuntimeAdapter["apply"],
    configuration: Parameters<ConfigurationRuntimeAdapter["apply"]>[0],
    plan: ConfigurationRuntimePlan,
    mode: HostApplyMode
  ): Promise<HostRuntimeOperationResult> {
    const result = await operation(configuration, plan);

    if (mode === "preview" && !result.ok) {
      const backendLabel = state.selectedBackend ? displayBackendName(state.selectedBackend) : "selected backend";
      return {
        ok: true,
        message: `Preview noted ${backendLabel} gap: ${result.message ?? "unsupported host operation"}`
      };
    }

    return result;
  }

  function toHostRuntimeConfiguration(configuration: Parameters<ConfigurationRuntimeAdapter["apply"]>[0]): HostRuntimeConfiguration {
    return {
      id: configuration.id,
      name: configuration.name,
      inputs: configuration.inputs,
      outputs: configuration.outputs,
      monitors: configuration.monitors,
      routes: configuration.routes
    };
  }

  function createUnavailableCommandRunner(): CommandRunner {
    return {
      async run(command, args) {
        return {
          command,
          args,
          exitCode: 1,
          stdout: "",
          stderr: "Host command runner is only available when live apply is armed in Tauri."
        };
      }
    };
  }

  function createTauriCommandRunner(): CommandRunner {
    return {
      async run(command, args, options) {
        if (!hasTauriRuntime()) {
          return {
            command,
            args,
            exitCode: 1,
            stdout: "",
            stderr: "Live host apply requires the Tauri desktop shell."
          };
        }

        try {
          const raw = await invoke<string>("run_audio_command", {
            command,
            args: [...args],
            timeoutMs: options?.timeoutMs
          });
          return parseCommandResult(raw, command, args);
        } catch (error) {
          return {
            command,
            args,
            exitCode: 1,
            stdout: "",
            stderr: error instanceof Error ? error.message : "Host command failed"
          };
        }
      }
    };
  }

  function parseCommandResult(raw: string, command: string, args: readonly string[]): CommandResult {
    const parsed = JSON.parse(raw) as Partial<CommandResult>;

    return {
      command: typeof parsed.command === "string" ? parsed.command : command,
      args: Array.isArray(parsed.args) ? parsed.args.filter((item): item is string => typeof item === "string") : args,
      exitCode: typeof parsed.exitCode === "number" ? parsed.exitCode : 1,
      stdout: typeof parsed.stdout === "string" ? parsed.stdout : "",
      stderr: typeof parsed.stderr === "string" ? parsed.stderr : "",
      ...(parsed.errorCode ? { errorCode: parsed.errorCode } : {})
    };
  }

  function parseStartupStatus(raw: string): StartupStatus {
    const parsed = JSON.parse(raw) as Partial<StartupStatus>;

    if (typeof parsed.enabled !== "boolean" || typeof parsed.path !== "string") {
      throw new Error("Startup status response is invalid.");
    }

    return {
      enabled: parsed.enabled,
      available: typeof parsed.available === "boolean" ? parsed.available : true,
      path: parsed.path,
      binary: typeof parsed.binary === "string" ? parsed.binary : "",
      message: typeof parsed.message === "string" ? parsed.message : "Startup status updated."
    };
  }

  function describeStartupRuntimeNote(status: StartupStatus, mode: "desktop" | "background"): string {
    if (!status.available) {
      return status.message;
    }

    if (mode === "desktop") {
      return status.enabled ? "Loopwire is set to start with this desktop session." : "Loopwire desktop autostart is off.";
    }

    return status.enabled ? "Loopwire will restore audio through a user systemd unit." : "Loopwire background restore is off.";
  }

  function updateRuntimeStatus(result: ConfigurationRuntimeResult): void {
    runtimeStatus = result.status;
    runtimeNote = result.ok ? describeRuntimeSuccess(result) : result.reason;
    runtimeActivity = result.log;
    runtimeActivityReason = result.plan.reason;
  }

  function describeRuntimeSuccess(result: ConfigurationRuntimeResult): string {
    const lastEntry = result.log.at(-1);
    return lastEntry?.message ?? "Configuration verified in the app runtime.";
  }

  function runtimeActivityTitle(reason: RuntimeTransactionReason | undefined): string {
    if (reason === "startup") {
      return "Startup restore";
    }

    if (reason === "backend-change") {
      return "Backend change";
    }

    return "Configuration switch";
  }

  function runtimeOperationLabel(operation: RuntimeOperation): string {
    const labels: Record<RuntimeOperation, string> = {
      unload: "Unload",
      apply: "Apply",
      verify: "Verify",
      rollback: "Rollback"
    };

    return labels[operation];
  }

  function runtimeActivityLabel(entry: RuntimeLogEntry): string {
    return `${runtimeOperationLabel(entry.operation)} ${configurationNameForRuntimeEntry(entry)}`;
  }

  function configurationNameForRuntimeEntry(entry: RuntimeLogEntry): string {
    return state.configurations.find((configuration) => configuration.id === entry.configurationId)?.name ?? entry.configurationId;
  }

  async function createNewConfiguration(): Promise<void> {
    const created = createConfiguration(
      state,
      {
        name: "Untitled Configuration",
        description: "New routing workspace."
      },
      new Date().toISOString()
    );

    await chooseConfiguration(created.configuration.id, created.state);
  }

  async function duplicateActiveConfiguration(): Promise<void> {
    const duplicated = duplicateConfiguration(state, activeConfiguration.id, new Date().toISOString());
    await chooseConfiguration(duplicated.configuration.id, duplicated.state);
  }

  async function deleteActiveConfiguration(): Promise<void> {
    if (state.configurations.length <= 1) {
      runtimeStatus = "failed";
      runtimeNote = "Loopwire must keep at least one configuration.";
      return;
    }

    const currentConfiguration = activeConfiguration;
    const fallbackConfiguration = state.configurations.find((configuration) => configuration.id !== currentConfiguration.id);

    if (!fallbackConfiguration) {
      runtimeStatus = "failed";
      runtimeNote = "No fallback configuration is available.";
      return;
    }

    const switchToken = ++configurationSwitchToken;
    configurationSwitchBusy = true;
    let switchResult: ConfigurationRuntimeResult;

    try {
      switchResult = await executeConfigurationSwitch(state, fallbackConfiguration.id);
    } catch (error) {
      switchResult = {
        ok: false,
        status: "failed",
        state,
        plan: createConfigurationSwitchPlan(state, fallbackConfiguration.id, new Date().toISOString()),
        log: [],
        reason: error instanceof Error ? error.message : "Configuration delete switch failed."
      };
    }

    if (!isCurrentConfigurationSwitch(switchToken)) {
      return;
    }

    if (!switchResult.ok) {
      updateRuntimeStatus(switchResult);
      configurationSwitchBusy = false;
      return;
    }

    const deleted = deleteConfiguration(switchResult.state, currentConfiguration.id, switchResult.state.appliedAt ?? new Date().toISOString());
    applyState(deleted.state);
    runtimeStatus = "verified";
    runtimeNote = `Deleted ${deleted.removedConfiguration.name}; ${fallbackConfiguration.name} is verified in the app runtime.`;
    configurationSwitchBusy = false;
  }

  function handleNameChange(event: Event): void {
    const name = (event.currentTarget as HTMLInputElement).value;
    const updated = updateConfiguration(state, activeConfiguration.id, { name }, new Date().toISOString());
    applyState(updated.state);
    runtimeStatus = "verified";
    runtimeNote = `Saved ${updated.configuration.name}.`;
  }

  function handleDescriptionChange(event: Event): void {
    const description = (event.currentTarget as HTMLTextAreaElement).value;
    const updated = updateConfiguration(state, activeConfiguration.id, { description }, new Date().toISOString());
    applyState(updated.state);
    runtimeStatus = "verified";
    runtimeNote = `Saved notes for ${updated.configuration.name}.`;
  }

  function exportActiveConfiguration(): void {
    transferText = exportConfiguration(activeConfiguration);
    transferOpen = true;
    transferNote = `Exported ${activeConfiguration.name}.`;
  }

  async function importConfigurationFromText(): Promise<void> {
    const imported = importConfiguration(state, transferText, new Date().toISOString());

    if (!imported.ok) {
      transferNote = imported.reason;
      runtimeStatus = "failed";
      runtimeNote = imported.reason;
      return;
    }

    transferNote = `Imported ${imported.configuration.name}.`;
    await chooseConfiguration(imported.configuration.id, imported.state);
  }

  function hasTauriRuntime(): boolean {
    return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
  }

  function describeRoute(routeId: string): string {
    const route = activeConfiguration.routes.find((candidate) => candidate.id === routeId);

    if (!route) {
      return routeId;
    }

    return `${describeEndpoint(route.from)} to ${describeEndpoint(route.to)}`;
  }

  function describeRouteLabel(configuration: LoopwireConfiguration, route: AudioRoute): string {
    const endpoints = [...configuration.inputs, ...configuration.outputs, ...configuration.monitors];
    const from = endpoints.find((endpoint) => endpoint.id === route.from)?.label ?? route.from;
    const to = endpoints.find((endpoint) => endpoint.id === route.to)?.label ?? route.to;
    return `${from} to ${to}`;
  }

  function describeEndpoint(endpointId: string): string {
    const endpoints = [...activeConfiguration.inputs, ...activeConfiguration.outputs, ...activeConfiguration.monitors];
    return endpoints.find((endpoint) => endpoint.id === endpointId)?.label ?? endpointId;
  }

  function buildRoutingBoard(
    inputs: readonly AudioEndpoint[],
    outputs: readonly AudioEndpoint[],
    routes: readonly AudioRoute[]
  ): RoutingBoardModel {
    const inputIndexes = indexEndpointsById(inputs);
    const outputIndexes = indexEndpointsById(outputs);
    const rowCount = Math.max(inputs.length, outputs.length, routes.length, 1);
    const height = routingBoardTop + (rowCount - 1) * routingBoardRowGap + routingBoardBottom;
    const endpoints = [...inputs, ...outputs];
    const cables = routes.map((route, index) => {
      const sourceY = routingRowY(inputIndexes.get(route.from) ?? index);
      const routeY = routingRowY(index);
      const outputY = routingRowY(outputIndexes.get(route.to) ?? index);
      const d = `M 248 ${sourceY} C 340 ${sourceY}, 365 ${routeY}, 452 ${routeY} C 596 ${routeY}, 650 ${outputY}, 752 ${outputY}`;
      const gain = `${Math.round(route.gain * 100)}%`;

      return {
        id: route.id,
        d,
        label: `${endpointLabel(endpoints, route.from)} to ${endpointLabel(endpoints, route.to)} at ${gain}`,
        muted: route.muted
      };
    });

    return {
      cables,
      height,
      routeCount: routes.length,
      mutedCount: routes.filter((route) => route.muted).length
    };
  }

  function indexEndpointsById(endpoints: readonly AudioEndpoint[]): Map<string, number> {
    return new Map(endpoints.map((endpoint, index) => [endpoint.id, index]));
  }

  function endpointLabel(endpoints: readonly AudioEndpoint[], endpointId: string): string {
    return endpoints.find((endpoint) => endpoint.id === endpointId)?.label ?? endpointId;
  }

  function routingRowY(rowIndex: number): number {
    return routingBoardTop + rowIndex * routingBoardRowGap;
  }

  function backendNextAction(candidate: BackendCandidate): string {
    if (candidate.kind === state.selectedBackend) {
      return "Selected. This choice is saved and reused on startup.";
    }

    if (candidate.availability === "available") {
      return "Available for selection.";
    }

    if (candidate.kind === "jack") {
      return "Start a JACK server or install JACK tooling before selecting it.";
    }

    if (candidate.kind === "alsa") {
      return "Use PipeWire or PulseAudio for the main routing workflow; ALSA remains fallback diagnostics.";
    }

    return candidate.reason ?? "Open host diagnostics for details.";
  }

  function backendSelectionAction(candidate: BackendCandidate): string {
    if (candidate.kind === state.selectedBackend) {
      return "Selected";
    }

    if (candidate.availability !== "available") {
      return "Unavailable";
    }

    return "Select";
  }

  function describeBackendSelectionSummary(): string {
    if (backendDecision.mode === "none") {
      return "Live apply is locked until a backend probe succeeds.";
    }

    if (backendDecision.mode === "prompt") {
      return "Pick once to save the backend for this profile. Switching later stays in preview until re-armed.";
    }

    if (state.selectedBackend) {
      return `${selectedBackendName} is saved and will be reused for startup restore.`;
    }

    return `${backendDecision.backend.displayName} is the only available backend and has been selected automatically.`;
  }

  function describeBackendDetection(report: AudioBackendDetectionReport): string {
    const available = report.candidates.filter((candidate) => candidate.availability === "available");

    if (available.length === 0) {
      return "No Linux audio backend probes succeeded; open diagnostics for probe results.";
    }

    const names = available.map((candidate) => candidate.displayName).join(", ");

    if (available.length === 1) {
      return `Detected 1 available backend: ${names}.`;
    }

    return `Detected ${available.length} available backends: ${names}.`;
  }

  function describePlaybackDeviceReport(report: AudioPlaybackDeviceReport): string {
    if (report.devices.length > 0) {
      if (report.backend === "jack") {
        return `Detected ${report.devices.length} JACK input target(s).`;
      }

      if (report.backend === "alsa") {
        return `Detected ${report.devices.length} ALSA playback device(s) for diagnostics.`;
      }

      return `Detected ${report.devices.length} ${displayBackendName(report.backend)} playback sink target(s).`;
    }

    return report.diagnostics[0]?.message ?? `No ${displayBackendName(report.backend)} playback sinks were listed.`;
  }

  function describeInputSourceReport(report: AudioInputSourceReport): string {
    if (report.sources.length > 0) {
      if (report.backend === "jack") {
        return `Detected ${report.sources.length} JACK output source(s).`;
      }

      if (report.backend === "alsa") {
        return `Detected ${report.sources.length} ALSA capture device(s) for diagnostics.`;
      }

      return `Detected ${report.sources.length} ${displayBackendName(report.backend)} running app stream(s).`;
    }

    return report.diagnostics[0]?.message ?? `No ${displayBackendName(report.backend)} running app streams were listed.`;
  }

  function describeMonitorTargetListing(backend: AudioBackendKind): string {
    if (backend === "jack") {
      return "Listing JACK input ports.";
    }

    if (backend === "alsa") {
      return "Listing ALSA playback devices for diagnostics.";
    }

    return `Listing ${displayBackendName(backend)} playback sinks.`;
  }

  function describeSourceListing(backend: AudioBackendKind): string {
    if (backend === "jack") {
      return "Listing JACK output ports.";
    }

    if (backend === "alsa") {
      return "Listing ALSA capture devices for diagnostics.";
    }

    return `Listing ${displayBackendName(backend)} running app streams.`;
  }

  function toSourceCandidate(source: AudioInputSource): SourceCandidate {
    return {
      id: source.sourceId,
      category: sourceCategory(source.backend),
      label: source.label,
      detail: source.detail ?? source.sourceName,
      channels: source.channels,
      deviceName: source.sourceName
    };
  }

  function toHostOutputCandidate(device: AudioPlaybackDevice): OutputCandidate {
    const detail = device.detail ? `${device.deviceName} - ${device.detail}` : device.deviceName;

    return {
      id: `host-${device.backend}-${device.deviceName}`,
      category: outputCategory(device.backend),
      label: device.label,
      detail,
      channels: 2,
      deviceName: device.deviceName
    };
  }

  function sourceCategory(backend: AudioBackendKind): string {
    if (backend === "jack") {
      return "JACK ports";
    }

    if (backend === "alsa") {
      return "ALSA capture";
    }

    return "Running apps";
  }

  function outputCategory(backend: AudioBackendKind): string {
    if (backend === "jack") {
      return "JACK targets";
    }

    if (backend === "alsa") {
      return "ALSA playback";
    }

    return "Host targets";
  }

  function nativeBackendUsesHostTargets(kind: AudioBackendKind | undefined): boolean {
    return kind === "pipewire" || kind === "jack" || kind === "alsa";
  }

  function displayBackendName(kind: AudioBackendKind): string {
    return backendCandidates.find((candidate) => candidate.kind === kind)?.displayName ?? kind;
  }

  function backendCapabilityFor(kind: AudioBackendKind | undefined): RouteControlBackendCapability | undefined {
    return backendCapabilityReports.find((report) => report.kind === kind);
  }

  function routeGainControlLabel(routeId: string): string {
    const base = `Gain for ${describeRoute(routeId)}`;
    return routeGainEditingLocked && state.selectedBackend
      ? `${base}; locked at 100% for ${displayBackendName(state.selectedBackend)} live apply`
      : base;
  }

  function routeGainControlTitle(): string | undefined {
    if (!routeGainEditingLocked || !state.selectedBackend) {
      return undefined;
    }

    return routeControlSemantics.message;
  }

  function routeGainLockRuntimeNote(): string {
    if (!state.selectedBackend) {
      return "Choose a backend before editing route gain.";
    }

    return routeControlSemantics.message;
  }

  function startupBadge(enabled: boolean, available: boolean): string {
    if (!available) {
      return "blocked";
    }

    if (enabled) {
      return "enabled";
    }

    return "off";
  }

  function monitorTargetKnown(deviceName: string): boolean {
    return monitorTargetDevices.some((device) => device.deviceName === deviceName);
  }

  function describeMonitorTarget(monitor: { readonly deviceName?: string }): string {
    if (monitor.deviceName) {
      const matched = monitorTargetDevices.find((device) => device.deviceName === monitor.deviceName);
      return matched?.detail ? `${matched.deviceName} - ${matched.detail}` : monitor.deviceName;
    }

    return monitorTargetDevices.length > 0 ? "Loopwire will create a virtual monitor sink." : monitorTargetNote;
  }

  function describeHostBinding(endpoint: AudioEndpoint): string {
    return endpoint.deviceName ? endpoint.deviceName : "Manual host binding for native backend gaps.";
  }

  function hostBindingPlaceholder(role: AudioEndpoint["role"]): string {
    if (role === "input") {
      return "pw-link/JACK source port";
    }

    if (role === "output") {
      return "pw-link/JACK target port";
    }

    return "alsa_output...";
  }

  function hostBindingLabel(role: AudioEndpoint["role"]): string {
    if (role === "input") {
      return "Host source";
    }

    if (role === "output") {
      return "Host target";
    }

    return "Host sink";
  }

</script>

<svelte:head>
  <title>Loopwire</title>
</svelte:head>

<main class="shell" data-chrome={chromeMode}>
  {#if chromeMode === "custom"}
    <div class="custom-chrome" data-tauri-drag-region>
      <span>Loopwire</span>
      <div class="chrome-buttons" aria-label="Window controls">
        <button type="button" aria-label="Minimize window" on:click={() => void minimizeWindow()}>−</button>
        <button type="button" aria-label="Maximize or restore window" on:click={() => void toggleWindowMaximize()}>
          □
        </button>
        <button type="button" aria-label="Close window" on:click={() => void closeWindow()}>×</button>
      </div>
    </div>
  {/if}

  <section class="workspace">
    <aside class="sidebar" aria-label="Configurations">
      <div class="brand-block">
        <div class="mark" aria-hidden="true">
          <span></span>
        </div>
        <p class="eyebrow">Loopwire</p>
        <h1>Signal routing for Linux.</h1>
      </div>

      <div class="configuration-list">
        {#each state.configurations as configuration}
          <button
            type="button"
            class:active={configuration.id === state.activeConfigurationId}
            disabled={configurationSwitchBusy}
            on:click={() => void chooseConfiguration(configuration.id)}
          >
            <span>{configuration.name}</span>
            <small>{configuration.description}</small>
            <meter min="0" max="100" value={configuration.id === state.activeConfigurationId ? 100 : 72}>
              {configuration.id === state.activeConfigurationId ? 100 : 72}%
            </meter>
          </button>
        {/each}
      </div>

      <div class="configuration-actions" aria-label="Configuration actions">
        <button type="button" disabled={configurationSwitchBusy} on:click={() => void createNewConfiguration()}>New</button>
        <button type="button" disabled={configurationSwitchBusy} on:click={() => void duplicateActiveConfiguration()}>Duplicate</button>
        <button
          type="button"
          disabled={configurationSwitchBusy || state.configurations.length <= 1}
          on:click={() => void deleteActiveConfiguration()}
        >
          Delete
        </button>
      </div>

      <div
        class="boot-card"
        class:blocked={!startupAvailable}
        aria-label="Start on boot"
      >
        <div>
          <span>Open on boot</span>
          <strong>{startupBadge(startupEnabled, startupAvailable)}</strong>
        </div>
        <small>{startupNote}</small>
        <small class="path">{startupPath}</small>
        {#if startupBinary}
          <small class="path">Launcher {startupBinary}</small>
        {/if}
        <div class="boot-actions">
          <button type="button" disabled={startupBusy} on:click={() => void refreshStartupStatus()}>Check</button>
          <button
            type="button"
            disabled={startupActionDisabled}
            on:click={() => void setStartupEnabled(!startupEnabled)}
          >
            {startupEnabled ? "Disable" : "Enable"}
          </button>
        </div>
      </div>

      <div
        class="boot-card"
        class:blocked={!backgroundStartupAvailable}
        data-restore-summary={startupRestoreSummary.tone}
        aria-label="Restore on boot"
      >
        <div>
          <span>Restore on boot</span>
          <strong>{startupBadge(backgroundStartupEnabled, backgroundStartupAvailable)}</strong>
        </div>
        <small>{backgroundStartupNote}</small>
        <div class="restore-summary">
          <strong>{startupRestoreSummary.title}</strong>
          <small>{startupRestoreSummary.message}</small>
        </div>
        <small class="path">{backgroundStartupPath}</small>
        {#if backgroundStartupBinary}
          <small class="path">Launcher {backgroundStartupBinary}</small>
        {/if}
        <div class="boot-actions">
          <button
            type="button"
            disabled={backgroundStartupBusy}
            on:click={() => void runBackgroundStartupAction("background_status")}
          >
            Check
          </button>
          <button
            type="button"
            disabled={backgroundStartupActionDisabled}
            on:click={() => void setBackgroundStartupEnabled(!backgroundStartupEnabled)}
          >
            {backgroundStartupEnabled ? "Disable" : "Enable"}
          </button>
        </div>
      </div>

      <div class="startup-card">
        <span>Runtime</span>
        <strong>{runtimeStatus}</strong>
        <small>{runtimeNote}</small>
      </div>
    </aside>

    <section class="main-panel" aria-label="Active routing workspace">
      <header class="topbar">
        <div>
          <p class="eyebrow">{restoreNote} configuration</p>
          <h2>{activeConfiguration.name}</h2>
          <div class="configuration-editor" aria-label="Configuration metadata">
            <label>
              <span>Name</span>
              <input value={activeConfiguration.name} on:change={handleNameChange} />
            </label>
            <label>
              <span>Notes</span>
              <textarea rows="2" value={activeConfiguration.description} on:change={handleDescriptionChange}></textarea>
            </label>
          </div>
        </div>

        <div class="controls">
          <button type="button" class="source-button" on:click={() => (sourcePanelOpen = !sourcePanelOpen)}>
            {sourcePanelOpen ? "Close Sources" : "Add Source"}
          </button>

          <button type="button" class="source-button" on:click={() => (outputPanelOpen = !outputPanelOpen)}>
            {outputPanelOpen ? "Close Outputs" : "Add Output"}
          </button>

          <button type="button" class="source-button" on:click={() => (monitorPanelOpen = !monitorPanelOpen)}>
            {monitorPanelOpen ? "Close Monitors" : "Add Monitor"}
          </button>

          <button type="button" class="source-button secondary" on:click={exportActiveConfiguration}>
            Export
          </button>

          <button type="button" class="source-button secondary" on:click={() => (transferOpen = !transferOpen)}>
            Import
          </button>

          <button
            type="button"
            class="source-button secondary"
            aria-expanded={diagnosticsOpen}
            on:click={() => (diagnosticsOpen = !diagnosticsOpen)}
          >
            Diagnostics
          </button>

          <label>
            <span>Backend</span>
            <select value={selectedBackend} aria-label="Audio backend" on:change={handleBackendChange}>
              <option value="" disabled>Choose backend</option>
              {#each backendCandidates as candidate}
                <option value={candidate.kind} disabled={candidate.availability !== "available"}>
                  {candidate.displayName}
                </option>
              {/each}
            </select>
          </label>

          <label class="host-apply-control">
            <span>Host apply</span>
            <button
              type="button"
              class:armed={hostApplyMode === "live"}
              aria-pressed={hostApplyMode === "live"}
              disabled={hostApplyMode === "preview" && !liveApplyPreflight.ok}
              title={liveApplyPreflight.message}
              on:click={toggleHostApplyMode}
            >
              {hostApplyMode === "live" ? "Live armed" : "Preview"}
            </button>
          </label>

          <div class="chrome-control" data-mode={chromeModeSummary.tone} aria-label="Window chrome mode">
            <span>Chrome</span>
            <div class="segmented-control" role="group" aria-label="Choose window chrome mode">
              <button
                type="button"
                class:active={chromeMode === "native"}
                aria-pressed={chromeMode === "native"}
                on:click={() => void setChromeMode("native")}
              >
                Native
              </button>
              <button
                type="button"
                class:active={chromeMode === "custom"}
                aria-pressed={chromeMode === "custom"}
                on:click={() => void setChromeMode("custom")}
              >
                Fallback
              </button>
            </div>
            <strong>{chromeModeSummary.title}</strong>
            <small>{chromeModeSummary.message}</small>
          </div>
        </div>
      </header>

      <section class="backend-choice-panel" data-mode={backendDecision.mode} aria-label="Audio backend selection">
        <div class="section-heading compact">
          <div>
            <p class="eyebrow">Audio Backend</p>
            <h3>{selectedBackendName}</h3>
          </div>
          <span>{backendSelectionSummary}</span>
        </div>

        <div class="backend-choice-callout" data-tone={backendChoiceCallout.tone}>
          <div>
            <strong>{backendChoiceCallout.title}</strong>
            <p>{backendChoiceCallout.message}</p>
          </div>
          <span>{backendChoiceCallout.action}</span>
        </div>

        <div class="backend-choice-grid">
          {#each backendCandidates as candidate}
            <button
              type="button"
              class:selected={candidate.kind === state.selectedBackend}
              class:available={candidate.availability === "available"}
              disabled={candidate.availability !== "available"}
              aria-pressed={candidate.kind === state.selectedBackend}
              on:click={() => void chooseBackend(candidate.kind)}
            >
              <strong>{candidate.displayName}</strong>
              <small>{backendNextAction(candidate)}</small>
              <span>{backendSelectionAction(candidate)}</span>
            </button>
          {/each}
        </div>
      </section>

      <div class="status-stack">
        <div class="status-strip" data-mode={backendDecision.mode}>
          <span>{backendDecision.mode}</span>
          <p>{backendDecision.reason}</p>
        </div>

        <div class="status-strip runtime-strip" data-mode={runtimeStatus}>
          <span>{runtimeStatus}</span>
          <p>{runtimeNote}</p>
        </div>

        {#if runtimeActivity.length > 0}
          <div class="runtime-ledger" aria-label={runtimeActivityTitle(runtimeActivityReason)}>
            <span>{runtimeActivityTitle(runtimeActivityReason)}</span>
            <ol>
              {#each runtimeActivity as entry}
                <li class:failed={!entry.ok}>
                  <strong>{runtimeActivityLabel(entry)}</strong>
                  <small>{entry.message}</small>
                </li>
              {/each}
            </ol>
          </div>
        {/if}

        <div class="status-strip backend-detection-strip" data-mode={backendDecision.mode}>
          <span>Probe</span>
          <p>{backendDetectionNote}</p>
        </div>

        <div class="status-strip semantics-strip" data-mode={routeControlSemantics.mode}>
          <span>{routeControlSemantics.badge}</span>
          <p>{routeControlSemantics.message}</p>
        </div>

        <div
          class="status-strip preflight-strip"
          data-mode={liveApplyPreflight.mode}
          class:has-blockers={liveApplyPreflight.blockers.length > 1}
        >
          <span>{liveApplyPreflight.badge}</span>
          <div class="preflight-copy">
            <p>{liveApplyPreflight.message}</p>
            {#if liveApplyPreflight.blockers.length > 1}
              <ul aria-label="Live apply blockers">
                {#each liveApplyPreflight.blockers as blocker}
                  <li>{blocker}</li>
                {/each}
              </ul>
            {/if}
          </div>
          {#if canResetNativeRouteGains}
            <button type="button" class="preflight-action" on:click={resetNativeRouteGains}>
              Reset gains
            </button>
          {/if}
        </div>
      </div>

      {#if diagnosticsOpen}
        <section class="diagnostics-panel" aria-label="Backend diagnostics">
          <div class="section-heading compact">
            <div>
              <p class="eyebrow">Diagnostics</p>
              <h3>Backend Status</h3>
            </div>
            <span>{backendDetectionNote}</span>
          </div>

          <div class="backend-diagnostics">
            {#each backendCandidates as candidate}
              <article class:available={candidate.availability === "available"}>
                <strong>{candidate.displayName}</strong>
                <span>{candidate.availability}</span>
                <small>{backendNextAction(candidate)}</small>
              </article>
            {/each}
          </div>
        </section>
      {/if}

      {#if transferOpen}
        <section class="transfer-panel" aria-label="Configuration import and export">
          <div class="section-heading compact">
            <div>
              <p class="eyebrow">Configurations</p>
              <h3>Import / Export</h3>
            </div>
            <span>{transferNote}</span>
          </div>
          <textarea bind:value={transferText} rows="8" spellcheck="false"></textarea>
          <div class="transfer-actions">
            <button type="button" on:click={exportActiveConfiguration}>Export Active</button>
            <button type="button" on:click={() => void importConfigurationFromText()}>Import JSON</button>
            <button type="button" on:click={() => (transferOpen = false)}>Close</button>
          </div>
        </section>
      {/if}

      {#if sourcePanelOpen}
        <section class="source-picker" aria-label="Available sources">
          <div class="section-heading compact">
            <div>
              <p class="eyebrow">Source Picker</p>
              <h3>Add to {activeConfiguration.name}</h3>
            </div>
            <span>{sourcePickerCandidates.length} sources</span>
          </div>
          <p class="source-picker-note">{sourcePickerNote}</p>
          <div class="source-groups">
            {#each sourcePickerCandidates as source}
              <button
                type="button"
                disabled={sourceAlreadyAdded(source)}
                on:click={() => addSourceToActiveConfiguration(source)}
              >
                <strong>{source.label}</strong>
                <small>{sourceAlreadyAdded(source) ? "Already in this configuration" : `${source.category} · ${source.detail}`}</small>
              </button>
            {/each}
          </div>
        </section>
      {/if}

      {#if outputPanelOpen}
        <section class="output-picker" aria-label="Available outputs">
          <div class="section-heading compact">
            <div>
              <p class="eyebrow">Output Picker</p>
              <h3>Add to {activeConfiguration.name}</h3>
            </div>
            <span>{outputPickerCandidates.length} outputs</span>
          </div>
          <div class="output-groups">
            {#each outputPickerCandidates as output}
              <button
                type="button"
                disabled={outputAlreadyAdded(output)}
                on:click={() => addOutputToActiveConfiguration(output)}
              >
                <strong>{output.label}</strong>
                <small>{outputAlreadyAdded(output) ? "Already in this configuration" : `${output.category} · ${output.detail}`}</small>
              </button>
            {/each}
          </div>
        </section>
      {/if}

      {#if monitorPanelOpen}
        <section class="monitor-picker" aria-label="Available monitors">
          <div class="section-heading compact">
            <div>
              <p class="eyebrow">Monitor Picker</p>
              <h3>Add to {activeConfiguration.name}</h3>
            </div>
            <span>App runtime</span>
          </div>
          <div class="monitor-groups">
            {#each monitorCandidates as monitor}
              <button
                type="button"
                disabled={monitorAlreadyAdded(monitor)}
                on:click={() => addMonitorToActiveConfiguration(monitor)}
              >
                <strong>{monitor.label}</strong>
                <small>{monitorAlreadyAdded(monitor) ? "Already in this configuration" : monitor.detail}</small>
              </button>
            {/each}
          </div>
        </section>
      {/if}

      <section
        class="routing-board"
        aria-label="Routing graph"
        style={`--routing-board-height: ${routingBoard.height}px;`}
      >
        <div class="board-status" aria-label="Routing summary">
          <span>{routingBoard.routeCount} routes</span>
          <span>{routingBoard.mutedCount} muted</span>
          <span>{state.selectedBackend ? displayBackendName(state.selectedBackend) : "No backend"}</span>
        </div>

        <svg
          class="cables"
          viewBox={`0 0 1000 ${routingBoard.height}`}
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          {#each routingBoard.cables as cable}
            <path class:muted={cable.muted} d={cable.d}>
              <title>{cable.label}</title>
            </path>
          {/each}
        </svg>

        <div class="lane">
          <div class="lane-heading">
            <div>
              <h3>Sources</h3>
              <small>Application and hardware inputs</small>
            </div>
            <span>{activeConfiguration.inputs.length}</span>
          </div>
          {#each activeConfiguration.inputs as endpoint}
            <article class="node input-node">
              <div>
                <span>{endpoint.label}</span>
                <small>{endpoint.channels} channels</small>
              </div>
              <button
                type="button"
                class="node-remove"
                aria-label={`Remove source ${endpoint.label}`}
                title="Remove source"
                on:click={() => removeSourceFromActiveConfiguration(endpoint)}
              >
                ×
              </button>
              <i aria-hidden="true"></i>
              <label class="host-binding">
                <span>{hostBindingLabel(endpoint.role)}</span>
                <input
                  value={endpoint.deviceName ?? ""}
                  placeholder={hostBindingPlaceholder(endpoint.role)}
                  aria-label={`Host source for ${endpoint.label}`}
                  on:change={(event) => handleEndpointDeviceName(endpoint.id, event)}
                />
                <small>{describeHostBinding(endpoint)}</small>
              </label>
            </article>
          {/each}
        </div>

        <div class="lane route-lane">
          <div class="lane-heading">
            <div>
              <h3>Routes</h3>
              <small>{routeControlSemantics.badge}</small>
            </div>
            <span>{activeConfiguration.routes.length}</span>
          </div>
          {#if activeConfiguration.inputs.length > 0 && activeConfiguration.outputs.length > 0}
            <form class="route-create" on:submit|preventDefault={addSelectedRouteToActiveConfiguration}>
              <label>
                <span>From</span>
                <select bind:value={routeSourceId} aria-label="Route source">
                  {#each activeConfiguration.inputs as endpoint}
                    <option value={endpoint.id}>{endpoint.label}</option>
                  {/each}
                </select>
              </label>
              <label>
                <span>To</span>
                <select bind:value={routeOutputId} aria-label="Route output">
                  {#each activeConfiguration.outputs as endpoint}
                    <option value={endpoint.id}>{endpoint.label}</option>
                  {/each}
                </select>
              </label>
              <button type="submit" disabled={!canAddSelectedRoute}>
                {selectedRouteExists ? "Exists" : "Add"}
              </button>
            </form>
          {:else}
            <p class="empty-route-state">Add a source and output to create routes.</p>
          {/if}
          {#each activeConfiguration.routes as route}
            <article class="route" class:muted={route.muted}>
              <div class="route-summary">
                <span>{describeEndpoint(route.from)}</span>
                <strong>{Math.round(route.gain * 100)}%</strong>
                <span>{describeEndpoint(route.to)}</span>
              </div>
              <label class="route-slider" class:locked={routeGainEditingLocked}>
                <span>Gain</span>
                <input
                  type="range"
                  min="0"
                  max="100"
                  step="1"
                  value={Math.round(route.gain * 100)}
                  disabled={routeGainEditingLocked}
                  aria-label={routeGainControlLabel(route.id)}
                  title={routeGainControlTitle()}
                  on:input={(event) => handleRouteGain(route.id, event)}
                />
              </label>
              <div class="route-actions">
                <button
                  type="button"
                  class="mute-button"
                  aria-pressed={route.muted}
                  on:click={() => toggleRouteMuted(route.id)}
                >
                  {route.muted ? "Muted" : "Mute"}
                </button>
                <button
                  type="button"
                  class="route-remove"
                  aria-label={`Remove route ${describeRoute(route.id)}`}
                  title="Remove route"
                  on:click={() => removeRouteFromActiveConfiguration(route)}
                >
                  ×
                </button>
              </div>
            </article>
          {/each}
        </div>

        <div class="lane">
          <div class="lane-heading">
            <div>
              <h3>Outputs</h3>
              <small>Virtual buses and host targets</small>
            </div>
            <span>{activeConfiguration.outputs.length}</span>
          </div>
          {#each activeConfiguration.outputs as endpoint}
            <article class="node output-node">
              <i aria-hidden="true"></i>
              <div>
                <span>{endpoint.label}</span>
                <small>{endpoint.channels} channels</small>
              </div>
              <button
                type="button"
                class="node-remove"
                disabled={activeConfiguration.outputs.length <= 1}
                aria-label={`Remove output ${endpoint.label}`}
                title={activeConfiguration.outputs.length <= 1 ? "At least one output is required" : "Remove output"}
                on:click={() => removeOutputFromActiveConfiguration(endpoint)}
              >
                ×
              </button>
              <label class="host-binding">
                <span>{hostBindingLabel(endpoint.role)}</span>
                <input
                  value={endpoint.deviceName ?? ""}
                  placeholder={hostBindingPlaceholder(endpoint.role)}
                  aria-label={`Host target for ${endpoint.label}`}
                  on:change={(event) => handleEndpointDeviceName(endpoint.id, event)}
                />
                <small>{describeHostBinding(endpoint)}</small>
              </label>
            </article>
          {/each}
        </div>
      </section>

      <section class="monitor-section" aria-label="Monitors">
        <div class="section-heading">
          <div>
            <p class="eyebrow">Monitors</p>
            <h3>{visibleMonitors.length} visible</h3>
          </div>
          <span>{hiddenMonitorCount} hidden</span>
        </div>
        <p class="monitor-target-note">{monitorTargetNote}</p>

        <div class="monitor-grid">
          {#each visibleMonitors as monitor}
            <article>
              <div class="monitor-card-top">
                <button type="button" class="monitor-toggle" on:click={() => toggleMonitor(monitor.id)}>
                  <span>{monitor.label}</span>
                  <small>Visible</small>
                </button>
                <button
                  type="button"
                  class="node-remove monitor-remove"
                  aria-label={`Remove monitor ${monitor.label}`}
                  title="Remove monitor"
                  on:click={() => removeMonitorFromActiveConfiguration(monitor)}
                >
                  ×
                </button>
              </div>
              <label class="monitor-target-control">
                <span>Host sink</span>
                <select
                  value={monitor.deviceName ?? ""}
                  disabled={monitorTargetDevices.length === 0}
                  aria-label={`Detected host sink for ${monitor.label}`}
                  on:change={(event) => handleMonitorTargetSelection(monitor.id, event)}
                >
                  <option value="">Loopwire virtual monitor</option>
                  {#if monitor.deviceName && !monitorTargetKnown(monitor.deviceName)}
                    <option value={monitor.deviceName}>Manual: {monitor.deviceName}</option>
                  {/if}
                  {#each monitorTargetDevices as target}
                    <option value={target.deviceName}>{target.label}</option>
                  {/each}
                </select>
                <input
                  value={monitor.deviceName ?? ""}
                  placeholder={monitorTargetDevices.length > 0 ? "Manual sink override" : "alsa_output..."}
                  aria-label={`Manual host sink for ${monitor.label}`}
                  on:change={(event) => handleEndpointDeviceName(monitor.id, event)}
                />
                <small>{describeMonitorTarget(monitor)}</small>
              </label>
            </article>
          {/each}
        </div>

        {#if hiddenMonitors.length > 0}
          <div class="hidden-monitor-tray" aria-label="Hidden monitors">
            <div>
              <strong>{hiddenMonitors.length} hidden monitor{hiddenMonitors.length === 1 ? "" : "s"}</strong>
              <small>Hidden monitors stay saved in this configuration and can be restored without re-adding them.</small>
            </div>
            <div class="hidden-monitor-actions">
              {#each hiddenMonitors as monitor}
                <button type="button" on:click={() => toggleMonitor(monitor.id)}>
                  <span>{monitor.label}</span>
                  <small>Show</small>
                </button>
              {/each}
            </div>
          </div>
        {/if}
      </section>
    </section>
  </section>
</main>

<style>
  :global(*) {
    box-sizing: border-box;
  }

  :global(body) {
    margin: 0;
    min-width: 320px;
    color: #f4efe2;
    background: #101113;
    font-family:
      Avenir Next,
      Avenir,
      "Segoe UI",
      sans-serif;
  }

  button,
  input,
  select {
    font: inherit;
  }

  textarea {
    font: inherit;
  }

  button {
    cursor: pointer;
  }

  button:disabled {
    cursor: not-allowed;
    opacity: 0.48;
  }

  button:focus-visible,
  input:focus-visible,
  select:focus-visible,
  textarea:focus-visible {
    outline: 3px solid #46d6c8;
    outline-offset: 2px;
  }

  .shell {
    min-height: 100vh;
    background:
      radial-gradient(circle at 0 0, rgba(235, 83, 47, 0.24), transparent 30rem),
      linear-gradient(135deg, #121416 0%, #181511 42%, #101113 100%);
  }

  .custom-chrome {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 42px;
    padding: 0 12px 0 18px;
    color: #d8d0bf;
    background: rgba(16, 17, 19, 0.92);
    border-bottom: 1px solid rgba(244, 239, 226, 0.12);
  }

  .chrome-buttons {
    display: flex;
    gap: 8px;
  }

  .chrome-buttons button {
    display: grid;
    place-items: center;
    width: 30px;
    height: 28px;
    color: #f4efe2;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.18);
    border-radius: 6px;
  }

  .workspace {
    display: grid;
    grid-template-columns: minmax(220px, 280px) minmax(0, 1fr);
    gap: 18px;
    min-height: 100vh;
    padding: 18px;
  }

  .shell[data-chrome="custom"] .workspace {
    min-height: calc(100vh - 42px);
  }

  .sidebar,
  .main-panel {
    border: 1px solid rgba(244, 239, 226, 0.14);
    border-radius: 8px;
    background: rgba(21, 22, 22, 0.78);
    box-shadow: 0 28px 80px rgba(0, 0, 0, 0.38);
    backdrop-filter: blur(18px);
  }

  .sidebar {
    display: flex;
    flex-direction: column;
    gap: 28px;
    padding: 22px;
  }

  .brand-block h1,
  .topbar h2,
  .section-heading h3 {
    margin: 0;
    letter-spacing: 0;
  }

  .brand-block h1 {
    max-width: 8ch;
    font-family: Georgia, "Times New Roman", serif;
    font-size: 2.55rem;
    line-height: 0.95;
  }

  .mark {
    display: grid;
    place-items: center;
    width: 50px;
    height: 50px;
    margin-bottom: 14px;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
    border-radius: 8px;
  }

  .mark span {
    width: 26px;
    height: 26px;
    border: 6px solid #46d6c8;
    border-right-color: #eb532f;
    transform: rotate(45deg);
  }

  .eyebrow {
    margin: 0 0 8px;
    color: #f7b74a;
    font-size: 0.75rem;
    font-weight: 700;
    text-transform: uppercase;
  }

  .configuration-list {
    display: grid;
    gap: 10px;
  }

  .configuration-list button {
    display: grid;
    gap: 7px;
    width: 100%;
    min-height: 86px;
    padding: 14px;
    color: #f4efe2;
    text-align: left;
    background: #1c1b18;
    border: 1px solid rgba(244, 239, 226, 0.12);
    border-radius: 8px;
  }

  .configuration-list button.active {
    color: #101113;
    background: #c9f05a;
    border-color: #c9f05a;
  }

  .configuration-list meter {
    width: 100%;
    height: 8px;
    accent-color: #46d6c8;
  }

  .configuration-actions,
  .transfer-actions {
    display: grid;
    gap: 8px;
  }

  .configuration-actions {
    grid-template-columns: repeat(auto-fit, minmax(92px, 1fr));
  }

  .transfer-actions {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  .configuration-actions button,
  .transfer-actions button,
  .boot-actions button {
    min-height: 36px;
    color: #f4efe2;
    font-weight: 800;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
    border-radius: 6px;
  }

  .boot-card {
    display: grid;
    gap: 9px;
    padding: 14px;
    color: #d8d0bf;
    background: #171817;
    border: 1px solid rgba(244, 239, 226, 0.12);
    border-left: 4px solid #46d6c8;
    border-radius: 8px;
  }

  .boot-card.blocked {
    border-left-color: #f7b74a;
  }

  .boot-card[data-restore-summary="setup"] {
    border-left-color: #f7b74a;
  }

  .boot-card[data-restore-summary="blocked"] {
    border-left-color: #f05d5e;
  }

  .boot-card > div:first-child {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
  }

  .boot-card span {
    color: #46d6c8;
    font-size: 0.74rem;
    font-weight: 900;
    text-transform: uppercase;
  }

  .boot-card strong {
    color: #f4efe2;
  }

  .boot-card small {
    overflow-wrap: anywhere;
    line-height: 1.35;
  }

  .boot-card .path {
    color: #9f9789;
    font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
  }

  .restore-summary {
    display: grid;
    gap: 4px;
    padding: 10px;
    background: rgba(244, 239, 226, 0.05);
    border: 1px solid rgba(244, 239, 226, 0.1);
    border-radius: 6px;
  }

  .restore-summary strong {
    font-size: 0.86rem;
  }

  .boot-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  .startup-card {
    display: grid;
    gap: 5px;
    margin-top: auto;
    padding: 14px;
    color: #d8d0bf;
    background: #20201d;
    border: 1px solid rgba(244, 239, 226, 0.12);
    border-radius: 8px;
  }

  .startup-card span {
    color: #f7b74a;
    font-size: 0.74rem;
    font-weight: 800;
    text-transform: uppercase;
  }

  .startup-card strong {
    color: #f4efe2;
  }

  .startup-card small {
    overflow-wrap: anywhere;
  }

  .configuration-list span,
  .node span,
  .monitor-grid span {
    font-weight: 800;
  }

  small {
    color: inherit;
    opacity: 0.72;
  }

  .main-panel {
    display: grid;
    grid-template-rows: auto auto 1fr auto;
    gap: 16px;
    padding: 18px;
  }

  .topbar,
  .section-heading {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }

  .topbar h2 {
    font-size: 2.15rem;
  }

  .configuration-editor {
    display: grid;
    grid-template-columns: minmax(160px, 220px) minmax(220px, 360px);
    gap: 10px;
    margin-top: 12px;
  }

  .configuration-editor label {
    display: grid;
    gap: 6px;
    color: #d8d0bf;
    font-size: 0.78rem;
    font-weight: 700;
  }

  .controls {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }

  .controls label {
    display: grid;
    gap: 6px;
    color: #d8d0bf;
    font-size: 0.78rem;
    font-weight: 700;
  }

  .chrome-control {
    display: grid;
    gap: 6px;
    max-width: 260px;
    color: #d8d0bf;
    font-size: 0.78rem;
    font-weight: 700;
  }

  .chrome-control > span {
    color: #d8d0bf;
  }

  .chrome-control strong {
    color: #f4efe2;
    font-size: 0.82rem;
  }

  .chrome-control small {
    line-height: 1.35;
  }

  .segmented-control {
    display: grid;
    grid-template-columns: 1fr 1fr;
    min-height: 36px;
    padding: 3px;
    background: #171817;
    border: 1px solid rgba(244, 239, 226, 0.16);
    border-radius: 6px;
  }

  .segmented-control button {
    min-width: 78px;
    color: #d8d0bf;
    font-weight: 800;
    background: transparent;
    border: 0;
    border-radius: 4px;
  }

  .segmented-control button.active {
    color: #101113;
    background: #c9f05a;
  }

  .source-button {
    align-self: end;
    min-height: 37px;
    padding: 0 13px;
    color: #101113;
    font-weight: 800;
    background: #c9f05a;
    border: 0;
    border-radius: 6px;
  }

  .source-button.secondary {
    color: #f4efe2;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
  }

  .host-apply-control button {
    min-height: 36px;
    padding: 0 12px;
    color: #f4efe2;
    font-weight: 800;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
    border-radius: 6px;
  }

  .host-apply-control button.armed {
    color: #101113;
    background: #f7b74a;
    border-color: #f7b74a;
  }

  input,
  select {
    min-width: 150px;
    color: #f4efe2;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.18);
    border-radius: 6px;
    padding: 8px 10px;
  }

  textarea {
    width: 100%;
    resize: vertical;
    color: #f4efe2;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.18);
    border-radius: 6px;
    padding: 8px 10px;
  }

  .status-stack {
    display: grid;
    gap: 10px;
  }

  .backend-choice-panel {
    display: grid;
    gap: 12px;
    padding: 14px;
    color: #d8d0bf;
    background: #171817;
    border: 1px solid rgba(244, 239, 226, 0.13);
    border-left: 4px solid #46d6c8;
    border-radius: 8px;
  }

  .backend-choice-panel[data-mode="prompt"] {
    border-left-color: #c9f05a;
  }

  .backend-choice-panel[data-mode="none"] {
    border-left-color: #eb532f;
  }

  .backend-choice-panel .section-heading > span {
    max-width: 52ch;
    font-size: 0.86rem;
    line-height: 1.4;
    text-align: right;
  }

  .backend-choice-callout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 12px;
    align-items: center;
    min-height: 72px;
    padding: 12px;
    color: #101113;
    background: #46d6c8;
    border-radius: 8px;
  }

  .backend-choice-callout[data-tone="prompt"] {
    background: #c9f05a;
  }

  .backend-choice-callout[data-tone="blocked"] {
    color: #f4efe2;
    background: #eb532f;
  }

  .backend-choice-callout strong,
  .backend-choice-callout p,
  .backend-choice-callout span {
    min-width: 0;
    margin: 0;
    overflow-wrap: anywhere;
  }

  .backend-choice-callout strong {
    font-size: 0.98rem;
  }

  .backend-choice-callout p {
    margin-top: 4px;
    font-size: 0.86rem;
    line-height: 1.35;
  }

  .backend-choice-callout span {
    max-width: 22ch;
    font-size: 0.74rem;
    font-weight: 900;
    line-height: 1.2;
    text-align: right;
    text-transform: uppercase;
  }

  .backend-choice-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
    gap: 10px;
  }

  .backend-choice-grid button {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 7px 10px;
    align-items: start;
    min-height: 104px;
    padding: 12px;
    color: #d8d0bf;
    text-align: left;
    background: #20201d;
    border: 1px solid rgba(244, 239, 226, 0.13);
    border-radius: 8px;
  }

  .backend-choice-grid button.available {
    border-color: rgba(70, 214, 200, 0.34);
  }

  .backend-choice-grid button.selected {
    color: #101113;
    background: #c9f05a;
    border-color: #c9f05a;
  }

  .backend-choice-grid strong,
  .backend-choice-grid small {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .backend-choice-grid strong {
    color: inherit;
    font-size: 0.95rem;
  }

  .backend-choice-grid small {
    grid-column: 1 / -1;
    line-height: 1.35;
  }

  .backend-choice-grid span {
    padding: 4px 8px;
    color: #101113;
    font-size: 0.7rem;
    font-weight: 900;
    text-transform: uppercase;
    background: #f7b74a;
    border-radius: 999px;
  }

  .backend-choice-grid button.selected span {
    color: #f4efe2;
    background: #101113;
  }

  .status-strip {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 12px;
    min-height: 54px;
    padding: 12px 14px;
    color: #101113;
    background: #f7b74a;
    border-radius: 8px;
  }

  .status-strip[data-mode="prompt"] {
    background: #c9f05a;
  }

  .runtime-strip {
    color: #f4efe2;
    background: #20201d;
    border: 1px solid rgba(244, 239, 226, 0.12);
  }

  .runtime-strip[data-mode="applying"] {
    color: #101113;
    background: #46d6c8;
  }

  .runtime-strip[data-mode="verified"] {
    color: #101113;
    background: #c9f05a;
  }

  .runtime-strip[data-mode="failed"],
  .runtime-strip[data-mode="rolled_back"] {
    color: #101113;
    background: #eb532f;
  }

  .runtime-ledger {
    display: grid;
    grid-template-columns: minmax(110px, auto) 1fr;
    gap: 12px;
    padding: 12px 14px;
    color: #d8d0bf;
    background: #171817;
    border: 1px solid rgba(244, 239, 226, 0.12);
    border-radius: 8px;
  }

  .runtime-ledger > span {
    color: #46d6c8;
    font-size: 0.74rem;
    font-weight: 900;
    text-transform: uppercase;
  }

  .runtime-ledger ol {
    display: grid;
    gap: 6px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .runtime-ledger li {
    display: grid;
    grid-template-columns: minmax(92px, 150px) 1fr;
    gap: 10px;
    align-items: baseline;
    min-height: 24px;
    padding-left: 12px;
    border-left: 3px solid #c9f05a;
  }

  .runtime-ledger li.failed {
    border-left-color: #eb532f;
  }

  .runtime-ledger strong {
    color: #f4efe2;
    font-size: 0.82rem;
  }

  .runtime-ledger small {
    overflow-wrap: anywhere;
    line-height: 1.35;
  }

  .semantics-strip {
    color: #f4efe2;
    background: #20201d;
    border: 1px solid rgba(244, 239, 226, 0.12);
  }

  .preflight-strip {
    color: #101113;
    background: #c9f05a;
  }

  .preflight-strip[data-mode="blocked"] {
    color: #f4efe2;
    background: #20201d;
    border: 1px solid rgba(244, 239, 226, 0.12);
  }

  .preflight-strip[data-mode="blocked"] span {
    background: #eb532f;
  }

  .preflight-strip.has-blockers {
    align-items: flex-start;
  }

  .preflight-copy {
    flex: 1 1 220px;
    min-width: 0;
  }

  .preflight-copy p {
    margin: 0;
  }

  .preflight-copy ul {
    display: grid;
    gap: 5px;
    margin: 8px 0 0;
    padding: 0;
    list-style: none;
  }

  .preflight-copy li {
    position: relative;
    padding-left: 14px;
    line-height: 1.35;
  }

  .preflight-copy li::before {
    position: absolute;
    top: 0.62em;
    left: 0;
    width: 5px;
    height: 5px;
    content: "";
    background: #eb532f;
    border-radius: 999px;
  }

  .preflight-action {
    flex: 0 0 auto;
    min-height: 34px;
    padding: 0 12px;
    color: #101113;
    font-size: 0.78rem;
    font-weight: 900;
    background: #c9f05a;
    border: 0;
    border-radius: 6px;
  }

  .preflight-action:hover {
    background: #f4efe2;
  }

  .semantics-strip[data-mode="stream"],
  .semantics-strip[data-mode="link"] {
    color: #101113;
    background: #f7b74a;
  }

  .semantics-strip[data-mode="edge"] {
    color: #101113;
    background: #c9f05a;
  }

  .status-strip span {
    flex: 0 0 auto;
    min-width: 64px;
    padding: 5px 8px;
    color: #f4efe2;
    text-align: center;
    text-transform: uppercase;
    background: #101113;
    border-radius: 999px;
  }

  .status-strip p {
    flex: 1 1 220px;
    min-width: 0;
    margin: 0;
    font-weight: 700;
    overflow-wrap: anywhere;
  }

  .transfer-panel,
  .diagnostics-panel,
  .source-picker,
  .output-picker,
  .monitor-picker {
    display: grid;
    gap: 12px;
    padding: 14px;
    background: #20201d;
    border: 1px solid rgba(244, 239, 226, 0.13);
    border-radius: 8px;
  }

  .backend-diagnostics {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 10px;
  }

  .backend-diagnostics article {
    display: grid;
    gap: 7px;
    min-height: 104px;
    padding: 12px;
    color: #d8d0bf;
    background: #171817;
    border: 1px solid rgba(244, 239, 226, 0.13);
    border-left: 4px solid #eb532f;
    border-radius: 8px;
  }

  .backend-diagnostics article.available {
    border-left-color: #46d6c8;
  }

  .backend-diagnostics strong {
    color: #f4efe2;
  }

  .backend-diagnostics article > span {
    width: fit-content;
    padding: 4px 8px;
    color: #101113;
    font-size: 0.74rem;
    font-weight: 900;
    text-transform: uppercase;
    background: #f7b74a;
    border-radius: 999px;
  }

  .backend-diagnostics article.available > span {
    background: #c9f05a;
  }

  .transfer-panel textarea {
    min-height: 150px;
    font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
    font-size: 0.82rem;
    line-height: 1.45;
  }

  .compact h3 {
    margin: 0;
  }

  .source-groups,
  .output-groups,
  .monitor-groups {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 10px;
  }

  .source-groups button,
  .output-groups button,
  .monitor-groups button {
    display: grid;
    gap: 5px;
    min-height: 72px;
    padding: 12px;
    color: #f4efe2;
    text-align: left;
    background: #171817;
    border: 1px solid rgba(244, 239, 226, 0.13);
    border-radius: 8px;
  }

  .routing-board {
    position: relative;
    display: grid;
    grid-template-columns: 1fr 1.25fr 1fr;
    grid-template-rows: auto 1fr;
    gap: 14px;
    min-height: var(--routing-board-height, 330px);
  }

  .board-status {
    position: relative;
    z-index: 2;
    display: flex;
    grid-column: 1 / -1;
    flex-wrap: wrap;
    gap: 8px;
  }

  .board-status span {
    min-height: 28px;
    padding: 6px 10px;
    color: #101113;
    font-size: 0.76rem;
    font-weight: 900;
    text-transform: uppercase;
    background: #46d6c8;
    border-radius: 999px;
  }

  .board-status span:nth-child(2) {
    background: #f7b74a;
  }

  .board-status span:nth-child(3) {
    color: #f4efe2;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
  }

  .cables {
    position: absolute;
    inset: 0;
    z-index: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }

  .cables path {
    fill: none;
    stroke: #46d6c8;
    stroke-linecap: round;
    stroke-width: 4;
    opacity: 0.85;
    filter: drop-shadow(0 0 6px rgba(70, 214, 200, 0.22));
  }

  .cables path.muted {
    stroke: #9f9789;
    stroke-dasharray: 10 12;
    opacity: 0.48;
  }

  .lane {
    position: relative;
    z-index: 1;
    display: grid;
    align-content: start;
    gap: 12px;
    min-height: calc(var(--routing-board-height, 330px) - 42px);
    padding: 14px;
    background: #1c1d1b;
    border: 1px solid rgba(244, 239, 226, 0.1);
    border-radius: 8px;
  }

  .lane h3 {
    margin: 0 0 4px;
  }

  .lane-heading small {
    display: block;
    max-width: 18ch;
    overflow-wrap: anywhere;
  }

  .lane-heading {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .lane-heading span {
    display: grid;
    place-items: center;
    min-width: 28px;
    height: 28px;
    color: #101113;
    font-weight: 900;
    background: #f7b74a;
    border-radius: 999px;
  }

  .node,
  .route {
    display: grid;
    gap: 6px;
    min-height: 72px;
    padding: 13px;
    background: #20201d;
    border: 1px solid rgba(244, 239, 226, 0.12);
    border-radius: 8px;
  }

  .node {
    grid-template-columns: minmax(0, 1fr) auto 16px;
    align-items: center;
  }

  .node div {
    display: grid;
    gap: 6px;
    min-width: 0;
  }

  .node span,
  .node small {
    overflow-wrap: anywhere;
  }

  .node i {
    width: 12px;
    height: 12px;
    background: #46d6c8;
    border: 2px solid #101113;
    border-radius: 999px;
    box-shadow: 0 0 0 3px rgba(70, 214, 200, 0.2);
  }

  .host-binding {
    display: grid;
    grid-column: 1 / -1;
    gap: 5px;
    color: #d8d0bf;
    font-size: 0.72rem;
    font-weight: 800;
    text-transform: uppercase;
  }

  .host-binding input {
    width: 100%;
    min-width: 0;
    padding: 8px 9px;
    font-size: 0.78rem;
  }

  .host-binding small {
    color: #9f9789;
    line-height: 1.35;
    overflow-wrap: anywhere;
    text-transform: none;
  }

  .input-node {
    border-left: 4px solid #46d6c8;
  }

  .output-node {
    grid-template-columns: 16px minmax(0, 1fr) auto;
    border-left: 4px solid #eb532f;
  }

  .output-node i {
    background: #eb532f;
    box-shadow: 0 0 0 3px rgba(235, 83, 47, 0.2);
  }

  .node-remove {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    min-width: 28px;
    padding: 0;
    color: #f4efe2;
    font-size: 1rem;
    font-weight: 900;
    line-height: 1;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
    border-radius: 6px;
  }

  .node-remove:not(:disabled):hover {
    color: #101113;
    background: #eb532f;
    border-color: #eb532f;
  }

  .route-create {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto;
    align-items: end;
    gap: 8px;
    padding: 10px;
    background: #171817;
    border: 1px solid rgba(244, 239, 226, 0.12);
    border-radius: 8px;
  }

  .route-create label {
    display: grid;
    gap: 5px;
    min-width: 0;
    color: #d8d0bf;
    font-size: 0.72rem;
    font-weight: 800;
    text-transform: uppercase;
  }

  .route-create select {
    width: 100%;
    min-width: 0;
  }

  .route-create button {
    min-height: 36px;
    padding: 0 12px;
    color: #101113;
    font-weight: 900;
    background: #c9f05a;
    border: 0;
    border-radius: 6px;
  }

  .empty-route-state {
    margin: 0;
    color: #d8d0bf;
    font-size: 0.84rem;
    line-height: 1.4;
  }

  .route {
    min-height: 116px;
  }

  .route.muted {
    opacity: 0.62;
  }

  .route-summary {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    gap: 8px;
  }

  .route strong {
    color: #c9f05a;
  }

  .route-slider {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    align-items: center;
    gap: 10px;
    color: #d8d0bf;
    font-size: 0.78rem;
    font-weight: 800;
  }

  .route-slider.locked {
    color: #9f9789;
  }

  .route-slider input {
    width: 100%;
    min-width: 0;
    accent-color: #46d6c8;
  }

  .route-slider input:disabled {
    cursor: not-allowed;
    accent-color: #9f9789;
  }

  .route-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .mute-button {
    justify-self: start;
    min-height: 32px;
    padding: 0 11px;
    color: #f4efe2;
    font-weight: 800;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
    border-radius: 6px;
  }

  .mute-button[aria-pressed="true"] {
    color: #101113;
    background: #f7b74a;
  }

  .route-remove {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    min-width: 32px;
    padding: 0;
    color: #f4efe2;
    font-size: 1rem;
    font-weight: 900;
    line-height: 1;
    background: #24211c;
    border: 1px solid rgba(244, 239, 226, 0.16);
    border-radius: 6px;
  }

  .route-remove:hover {
    color: #101113;
    background: #eb532f;
    border-color: #eb532f;
  }

  .monitor-section {
    display: grid;
    gap: 12px;
  }

  .section-heading > span {
    color: #d8d0bf;
  }

  .source-picker-note,
  .monitor-target-note {
    margin: -4px 0 0;
    color: #d8d0bf;
    font-size: 0.86rem;
    overflow-wrap: anywhere;
  }

  .monitor-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
    gap: 10px;
  }

  .monitor-grid article {
    display: grid;
    gap: 10px;
    min-height: 118px;
    padding: 12px;
    color: #f4efe2;
    background: #1c1b18;
    border: 1px solid rgba(244, 239, 226, 0.13);
    border-radius: 8px;
  }

  .monitor-card-top {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: start;
    gap: 8px;
  }

  .monitor-toggle {
    display: grid;
    gap: 4px;
    min-width: 0;
    padding: 0;
    color: inherit;
    text-align: left;
    background: transparent;
    border: 0;
  }

  .monitor-remove {
    align-self: start;
  }

  .monitor-grid label {
    display: grid;
    gap: 6px;
    color: #d8d0bf;
    font-size: 0.76rem;
    text-transform: uppercase;
    letter-spacing: 0;
  }

  .monitor-grid input,
  .monitor-grid select {
    width: 100%;
    min-width: 0;
    padding: 9px 10px;
    color: #f4efe2;
    background: rgba(16, 17, 19, 0.72);
    border: 1px solid rgba(244, 239, 226, 0.14);
    border-radius: 6px;
  }

  .monitor-target-control small {
    overflow-wrap: anywhere;
    color: #9f9789;
    line-height: 1.35;
    text-transform: none;
  }

  .hidden-monitor-tray {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 12px;
    align-items: center;
    padding: 12px;
    color: #d8d0bf;
    background: rgba(16, 17, 19, 0.68);
    border: 1px dashed rgba(244, 239, 226, 0.22);
    border-radius: 8px;
  }

  .hidden-monitor-tray strong,
  .hidden-monitor-tray small,
  .hidden-monitor-actions span,
  .hidden-monitor-actions small {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .hidden-monitor-tray strong {
    display: block;
    margin-bottom: 4px;
    color: #f4efe2;
  }

  .hidden-monitor-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: flex-end;
  }

  .hidden-monitor-actions button {
    display: grid;
    gap: 2px;
    min-width: 92px;
    padding: 8px 10px;
    color: #101113;
    text-align: left;
    background: #c9f05a;
    border: 0;
    border-radius: 8px;
  }

  .hidden-monitor-actions small {
    font-size: 0.7rem;
    font-weight: 900;
    text-transform: uppercase;
  }

  @media (max-width: 860px) {
    .workspace,
    .routing-board {
      grid-template-columns: 1fr;
    }

    .main-panel {
      order: -1;
    }

    .routing-board {
      min-height: auto;
    }

    .lane {
      min-height: auto;
    }

    .route-create {
      grid-template-columns: 1fr;
    }

    .route-create button {
      width: 100%;
    }

    .runtime-ledger,
    .runtime-ledger li {
      grid-template-columns: 1fr;
    }

    .brand-block h1 {
      max-width: none;
      font-size: 2.2rem;
    }

    .topbar {
      align-items: flex-start;
      flex-direction: column;
    }

    .backend-choice-panel .section-heading {
      align-items: flex-start;
      flex-direction: column;
    }

    .backend-choice-panel .section-heading > span {
      max-width: none;
      text-align: left;
    }

    .backend-choice-callout {
      grid-template-columns: 1fr;
    }

    .backend-choice-callout span {
      max-width: none;
      text-align: left;
    }

    .hidden-monitor-tray {
      grid-template-columns: 1fr;
    }

    .hidden-monitor-actions {
      justify-content: stretch;
    }

    .hidden-monitor-actions button {
      flex: 1 1 120px;
    }

    .cables {
      display: none;
    }

    .configuration-editor {
      grid-template-columns: 1fr;
    }
  }
</style>
