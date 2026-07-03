import { spawn } from "node:child_process";
import type { CommandResult, CommandRunOptions, CommandRunner } from "./types.js";

const defaultTimeoutMs = 3500;

export function createNodeCommandRunner(): CommandRunner {
  return {
    run(command, args, options) {
      return runCommand(command, args, options);
    }
  };
}

function runCommand(command: string, args: readonly string[], options: CommandRunOptions = {}): Promise<CommandResult> {
  return new Promise((resolve) => {
    const child = spawn(command, [...args], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    const timeoutMs = options.timeoutMs ?? defaultTimeoutMs;
    let settled = false;
    let timedOut = false;

    const finish = (result: CommandResult): void => {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timer);
      resolve(result);
    };

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
    }, timeoutMs);

    child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk));
    child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));

    child.on("error", (error: NodeJS.ErrnoException) => {
      finish({
        command,
        args,
        exitCode: 127,
        stdout: "",
        stderr: error.message,
        errorCode: error.code === "ENOENT" ? "missing" : "failed"
      });
    });

    child.on("close", (code: number | null) => {
      finish({
        command,
        args,
        exitCode: timedOut ? 124 : (code ?? 1),
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
        ...(timedOut ? { errorCode: "timeout" } : {})
      });
    });
  });
}
