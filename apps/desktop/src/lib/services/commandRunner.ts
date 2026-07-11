import { invoke } from "@tauri-apps/api/core";
import type { CommandResult, CommandRunner } from "@loopwire/audio-host/runtime";
import { hasTauriRuntime } from "./statePersistence";

/** Runs host audio commands through the Tauri shell's `run_audio_command`. */
export function createTauriCommandRunner(): CommandRunner {
  return {
    async run(command, args, options) {
      if (!hasTauriRuntime()) {
        return {
          command,
          args,
          exitCode: 1,
          stdout: "",
          stderr: "Host commands require the Loopwire desktop shell."
        };
      }

      try {
        const raw = await invoke<string>("run_audio_command", {
          command,
          args: [...args],
          timeoutMs: options?.timeoutMs,
          input: options?.input
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

/** Refuses to run anything; used for dry-run/preview transactions. */
export function createUnavailableCommandRunner(): CommandRunner {
  return {
    async run(command, args) {
      return {
        command,
        args,
        exitCode: 1,
        stdout: "",
        stderr: "Host command runner is only available when live apply is armed in the desktop shell."
      };
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
