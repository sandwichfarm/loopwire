import {
  isMonitorHidden,
  setMonitorHidden,
  type LoopwireConfiguration,
  type LoopwireState
} from "@loopwire/core";

export interface MonitorVisibilityGroups {
  readonly visible: LoopwireConfiguration["monitors"];
  readonly hidden: LoopwireConfiguration["monitors"];
}

export function groupMonitorsByVisibility(
  state: LoopwireState,
  configuration: LoopwireConfiguration
): MonitorVisibilityGroups {
  const visible: LoopwireConfiguration["monitors"][number][] = [];
  const hidden: LoopwireConfiguration["monitors"][number][] = [];

  for (const monitor of configuration.monitors) {
    if (isMonitorHidden(state, configuration, monitor.id)) {
      hidden.push(monitor);
    } else {
      visible.push(monitor);
    }
  }

  return { visible, hidden };
}

export function restoreHiddenMonitors(
  state: LoopwireState,
  configuration: LoopwireConfiguration
): LoopwireState {
  return configuration.monitors.reduce(
    (nextState, monitor) => setMonitorHidden(nextState, configuration.id, monitor.id, false),
    state
  );
}
