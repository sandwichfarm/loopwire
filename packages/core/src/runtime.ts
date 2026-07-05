import { activateConfiguration, getActiveConfiguration, getConfigurationById, setSelectedBackend } from "./configuration.js";
import type { AudioBackendKind } from "./types.js";
import type { LoopwireConfiguration, LoopwireState } from "./types.js";

export type RuntimeOperation = "unload" | "apply" | "verify" | "rollback";
export type RuntimeTransactionReason = "switch" | "startup" | "backend-change";
export type RuntimeStatus = "verified" | "failed" | "rolled_back";

export interface RuntimeOperationResult {
  readonly ok: boolean;
  readonly message?: string;
}

export interface ConfigurationRuntimeAdapter {
  readonly unload: RuntimeAdapterOperation;
  readonly apply: RuntimeAdapterOperation;
  readonly verify: RuntimeAdapterOperation;
  readonly rollback: RuntimeAdapterOperation;
}

export interface ConfigurationRuntimePlan {
  readonly id: string;
  readonly reason: RuntimeTransactionReason;
  readonly toConfigurationId: string;
  readonly operations: readonly RuntimeOperation[];
  readonly createdAt: string;
  readonly fromConfigurationId?: string;
}

export interface RuntimeLogEntry {
  readonly operation: RuntimeOperation;
  readonly configurationId: string;
  readonly ok: boolean;
  readonly message: string;
}

export type ConfigurationRuntimeResult =
  | {
      readonly ok: true;
      readonly status: "verified";
      readonly state: LoopwireState;
      readonly plan: ConfigurationRuntimePlan;
      readonly log: readonly RuntimeLogEntry[];
    }
  | {
      readonly ok: false;
      readonly status: "failed" | "rolled_back";
      readonly state: LoopwireState;
      readonly plan: ConfigurationRuntimePlan;
      readonly log: readonly RuntimeLogEntry[];
      readonly reason: string;
    };

type RuntimeAdapterOperation = (
  configuration: LoopwireConfiguration,
  plan: ConfigurationRuntimePlan
) => RuntimeOperationResult | Promise<RuntimeOperationResult>;

export function createConfigurationSwitchPlan(
  state: LoopwireState,
  targetConfigurationId: string,
  createdAt: string
): ConfigurationRuntimePlan {
  const fromConfiguration = getActiveConfiguration(state);
  const toConfiguration = getConfigurationById(state, targetConfigurationId);
  const operations: RuntimeOperation[] =
    fromConfiguration.id === toConfiguration.id ? ["apply", "verify"] : ["unload", "apply", "verify"];

  return {
    id: `switch-${fromConfiguration.id}-${toConfiguration.id}-${createdAt}`,
    reason: "switch",
    fromConfigurationId: fromConfiguration.id,
    toConfigurationId: toConfiguration.id,
    operations,
    createdAt
  };
}

export function createStartupVerificationPlan(state: LoopwireState, createdAt: string): ConfigurationRuntimePlan {
  const toConfiguration = getActiveConfiguration(state);

  return {
    id: `startup-${toConfiguration.id}-${createdAt}`,
    reason: "startup",
    toConfigurationId: toConfiguration.id,
    operations: ["apply", "verify"],
    createdAt
  };
}

export function createBackendSelectionPlan(state: LoopwireState, createdAt: string): ConfigurationRuntimePlan {
  const toConfiguration = getActiveConfiguration(state);

  return {
    id: `backend-change-${toConfiguration.id}-${createdAt}`,
    reason: "backend-change",
    toConfigurationId: toConfiguration.id,
    operations: ["apply", "verify"],
    createdAt
  };
}

export async function applyConfigurationSwitch(
  state: LoopwireState,
  targetConfigurationId: string,
  adapter: ConfigurationRuntimeAdapter,
  appliedAt: string
): Promise<ConfigurationRuntimeResult> {
  const plan = createConfigurationSwitchPlan(state, targetConfigurationId, appliedAt);
  return runConfigurationPlan(state, plan, adapter, appliedAt);
}

export async function verifyStartupConfiguration(
  state: LoopwireState,
  adapter: ConfigurationRuntimeAdapter,
  appliedAt: string
): Promise<ConfigurationRuntimeResult> {
  const plan = createStartupVerificationPlan(state, appliedAt);
  return runConfigurationPlan(state, plan, adapter, appliedAt);
}

export async function applyBackendSelection(
  state: LoopwireState,
  selectedBackend: AudioBackendKind,
  adapter: ConfigurationRuntimeAdapter,
  appliedAt: string
): Promise<ConfigurationRuntimeResult> {
  const nextState = setSelectedBackend(state, selectedBackend);
  const plan = createBackendSelectionPlan(nextState, appliedAt);
  const result = await runConfigurationPlan(nextState, plan, adapter, appliedAt);

  if (!result.ok) {
    return {
      ...result,
      state
    };
  }

  return result;
}

async function runConfigurationPlan(
  state: LoopwireState,
  plan: ConfigurationRuntimePlan,
  adapter: ConfigurationRuntimeAdapter,
  appliedAt: string
): Promise<ConfigurationRuntimeResult> {
  const log: RuntimeLogEntry[] = [];
  const targetConfiguration = getConfigurationById(state, plan.toConfigurationId);

  for (const operation of plan.operations) {
    const configuration = configurationForOperation(state, targetConfiguration, plan, operation);
    const result = await callRuntimeOperation(adapter, operation, configuration, plan);
    log.push(toLogEntry(operation, configuration.id, result));

    if (!result.ok) {
      return handleRuntimeFailure(state, plan, adapter, operation, result.message ?? `${operation} failed`, log);
    }
  }

  return {
    ok: true,
    status: "verified",
    state: activateConfiguration(state, targetConfiguration.id, appliedAt),
    plan,
    log
  };
}

function configurationForOperation(
  state: LoopwireState,
  targetConfiguration: LoopwireConfiguration,
  plan: ConfigurationRuntimePlan,
  operation: RuntimeOperation
): LoopwireConfiguration {
  if (operation === "unload" && plan.fromConfigurationId) {
    return getConfigurationById(state, plan.fromConfigurationId);
  }

  if (operation === "rollback") {
    return getRollbackConfiguration(state, targetConfiguration, plan);
  }

  return targetConfiguration;
}

async function handleRuntimeFailure(
  state: LoopwireState,
  plan: ConfigurationRuntimePlan,
  adapter: ConfigurationRuntimeAdapter,
  failedOperation: RuntimeOperation,
  reason: string,
  log: RuntimeLogEntry[]
): Promise<ConfigurationRuntimeResult> {
  if (failedOperation === "unload") {
    return { ok: false, status: "failed", state, plan, log, reason };
  }

  const targetConfiguration = getConfigurationById(state, plan.toConfigurationId);
  const rollbackConfiguration = getRollbackConfiguration(state, targetConfiguration, plan);
  const rollbackResult = await callRuntimeOperation(adapter, "rollback", rollbackConfiguration, plan);
  log.push(toLogEntry("rollback", rollbackConfiguration.id, rollbackResult));

  return {
    ok: false,
    status: "rolled_back",
    state,
    plan,
    log,
    reason: rollbackResult.ok ? reason : `${reason}; rollback failed: ${rollbackResult.message ?? "unknown error"}`
  };
}

function getRollbackConfiguration(
  state: LoopwireState,
  targetConfiguration: LoopwireConfiguration,
  plan: ConfigurationRuntimePlan
): LoopwireConfiguration {
  return plan.fromConfigurationId ? getConfigurationById(state, plan.fromConfigurationId) : targetConfiguration;
}

async function callRuntimeOperation(
  adapter: ConfigurationRuntimeAdapter,
  operation: RuntimeOperation,
  configuration: LoopwireConfiguration,
  plan: ConfigurationRuntimePlan
): Promise<RuntimeOperationResult> {
  try {
    return await adapter[operation](configuration, plan);
  } catch (error) {
    return {
      ok: false,
      message: error instanceof Error ? error.message : `${operation} failed`
    };
  }
}

function toLogEntry(operation: RuntimeOperation, configurationId: string, result: RuntimeOperationResult): RuntimeLogEntry {
  return {
    operation,
    configurationId,
    ok: result.ok,
    message: result.message ?? (result.ok ? "ok" : "failed")
  };
}
