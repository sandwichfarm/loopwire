import { describe, expect, it } from "vitest";
import { createNodeCommandRunner } from "../src/index.js";

describe("createNodeCommandRunner", () => {
  it("passes optional stdin input to spawned commands", async () => {
    const runner = createNodeCommandRunner();
    const result = await runner.run(
      process.execPath,
      [
        "-e",
        [
          "let input = '';",
          "process.stdin.setEncoding('utf8');",
          "process.stdin.on('data', (chunk) => { input += chunk; });",
          "process.stdin.on('end', () => { process.stdout.write(input.toUpperCase()); });"
        ].join("")
      ],
      { input: "loopwire" }
    );

    expect(result).toMatchObject({
      exitCode: 0,
      stdout: "LOOPWIRE",
      stderr: ""
    });
  });
});
