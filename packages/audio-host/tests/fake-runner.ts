import type { CommandResult, CommandRunner } from "../src/index.js";

type CommandKey = string;

export function createFakeRunner(results: Record<CommandKey, Partial<CommandResult>>): CommandRunner {
  return {
    async run(command, args) {
      const key = commandKey(command, args);
      const result = results[key] ?? results[command];

      if (!result) {
        return {
          command,
          args,
          exitCode: 127,
          stdout: "",
          stderr: `${command}: command not found`,
          errorCode: "missing"
        };
      }

      const commandResult: CommandResult = {
        command,
        args,
        exitCode: result.exitCode ?? 0,
        stdout: result.stdout ?? "",
        stderr: result.stderr ?? ""
      };

      return result.errorCode ? { ...commandResult, errorCode: result.errorCode } : commandResult;
    }
  };
}

function commandKey(command: string, args: readonly string[]): string {
  return [command, ...args].join(" ");
}
