import {
  setRouteGain,
  type AudioBackendKind,
  type AudioRoute,
  type LoopwireConfiguration,
  type LoopwireState
} from "@loopwire/core";
import { getNativeGainBlockerRoutes, type LiveApplyBackendCapability } from "./live-apply-preflight";

export interface NativeRouteGainResetInput {
  readonly state: LoopwireState;
  readonly configuration: LoopwireConfiguration;
  readonly backend: AudioBackendKind | undefined;
  readonly capability?: LiveApplyBackendCapability | undefined;
  readonly updatedAt: string;
}

export interface NativeRouteGainResetResult {
  readonly state: LoopwireState;
  readonly routes: readonly AudioRoute[];
}

export function resetNativeRouteGainsForLiveApply(input: NativeRouteGainResetInput): NativeRouteGainResetResult {
  const routes = getNativeGainBlockerRoutes(input.configuration, input.backend, input.capability);
  let nextState = input.state;

  for (const route of routes) {
    nextState = setRouteGain(nextState, input.configuration.id, route.id, 1, input.updatedAt).state;
  }

  return {
    state: nextState,
    routes
  };
}
