/**
 * Composition root for the desktop UI. Container components import these
 * singletons; leaf components stay props-only. Tests use the create* factories
 * directly and never import this module.
 */
import { createDeviceStore } from "./stores/deviceStore";
import { createLevelStore, silentLevelProvider } from "./stores/levelStore";
import { createUiStore } from "./stores/uiStore";
import { createHostCatalog } from "./services/hostCatalog";
import { createRuntimeService } from "./services/runtime";
import { createStatePersistence } from "./services/statePersistence";
import { createThemeService } from "./services/theme";

export const uiStore = createUiStore();

export const deviceStore = createDeviceStore(
  createStatePersistence((message) => uiStore.pushToast("error", message))
);

/**
 * Per-port levels. The PipeWire adapter has no level stream yet (documented
 * capability gap), so this stays silent and meters render their empty track.
 */
export const levelStore = createLevelStore(silentLevelProvider);

export const hostCatalog = createHostCatalog();

export const themeService = createThemeService();

export const runtimeService = createRuntimeService(deviceStore, (message) => uiStore.pushToast("error", message));
