import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Loopwire",
  description: "Linux virtual audio routing with a world-class desktop UX.",
  cleanUrls: true,
  lastUpdated: true,
  themeConfig: {
    logo: "/loopwire-mark.svg",
    nav: [
      { text: "Install", link: "/guide/install" },
      { text: "Configurations", link: "/guide/configurations" },
      { text: "Backends", link: "/guide/backends" },
      { text: "Support Matrix", link: "/guide/support-matrix" },
      { text: "Start on Boot", link: "/guide/start-on-boot" },
      { text: "Troubleshooting", link: "/guide/troubleshooting" },
      { text: "Architecture", link: "/developer/architecture" },
      { text: "Release", link: "/developer/release" }
    ],
    sidebar: [
      {
        text: "Guide",
        items: [
          { text: "Install", link: "/guide/install" },
          { text: "Configurations", link: "/guide/configurations" },
          { text: "Audio Backends", link: "/guide/backends" },
          { text: "Support Matrix", link: "/guide/support-matrix" },
          { text: "Start on Boot", link: "/guide/start-on-boot" },
          { text: "Troubleshooting", link: "/guide/troubleshooting" }
        ]
      },
      {
        text: "Developer",
        items: [
          { text: "Architecture", link: "/developer/architecture" },
          { text: "Screenshots", link: "/developer/screenshots" },
          { text: "End-to-End UI Tests", link: "/developer/e2e" },
          { text: "VM Matrix", link: "/developer/vm-matrix" },
          { text: "Release", link: "/developer/release" },
          { text: "Release Notes", link: "/developer/release-notes" }
        ]
      },
      {
        text: "Release Notes",
        items: [
          { text: "v0.1.0", link: "/release-notes/0.1.0" },
          { text: "Unreleased", link: "/release-notes/unreleased" }
        ]
      }
    ],
    search: {
      provider: "local"
    },
    socialLinks: [{ icon: "github", link: "https://github.com/sandwichfarm/loopwire" }]
  }
});
