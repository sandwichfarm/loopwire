#!/usr/bin/env node

const pretty = process.argv.includes("--pretty");

try {
  const { createNodeCommandRunner } = await import("../packages/audio-host/dist/command-runner.js");
  const { detectAudioBackends } = await import("../packages/audio-host/dist/detectors.js");
  const report = await detectAudioBackends(createNodeCommandRunner());

  process.stdout.write(`${JSON.stringify(report, null, pretty ? 2 : 0)}\n`);
} catch (error) {
  if (error?.code === "ERR_MODULE_NOT_FOUND") {
    console.error("Audio-host package is not built. Run: pnpm --filter @loopwire/audio-host build");
    process.exit(1);
  }

  throw error;
}
