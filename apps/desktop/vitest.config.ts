import { defineConfig } from "vitest/config";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  resolve: {
    alias: {
      "@loopwire/audio-host/detectors": fileURLToPath(new URL("../../packages/audio-host/src/detectors.ts", import.meta.url)),
      "@loopwire/audio-host/runtime": fileURLToPath(new URL("../../packages/audio-host/src/runtime-browser.ts", import.meta.url)),
      "@loopwire/core": fileURLToPath(new URL("../../packages/core/src/index.ts", import.meta.url))
    }
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"]
  }
});
