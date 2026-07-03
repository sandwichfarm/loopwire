import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";
import { fileURLToPath, URL } from "node:url";

export default defineConfig({
  plugins: [svelte()],
  resolve: {
    alias: {
      "@loopwire/audio-host/runtime": fileURLToPath(new URL("../../packages/audio-host/src/runtime-browser.ts", import.meta.url)),
      "@loopwire/core": fileURLToPath(new URL("../../packages/core/src/index.ts", import.meta.url))
    }
  },
  server: {
    strictPort: true
  }
});
