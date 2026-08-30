import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Loopwire Docs",
  titleTemplate: ":title | Loopwire",
  description: "Install, configure, and verify Loopwire on Linux desktops.",
  lang: "en-US",
  base: "/docs/",
  cleanUrls: false,
  lastUpdated: true,
  head: [
    ["meta", { name: "theme-color", content: "#071014" }],
    ["meta", { name: "color-scheme", content: "dark" }],
    ["meta", { property: "og:site_name", content: "Loopwire Docs" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:image", content: "https://loopwire.app/docs/product-screenshot.png" }],
    ["meta", { name: "twitter:card", content: "summary_large_image" }]
  ],
  transformHead({ page }) {
    const route = page === "index.md" ? "" : page.replace(/\.md$/, ".html");
    const url = `https://loopwire.app/docs/${route}`;
    return [
      ["link", { rel: "canonical", href: url }],
      ["meta", { property: "og:url", content: url }]
    ];
  },
  themeConfig: {
    logo: "/loopwire-mark.svg",
    nav: [
      { text: "Home", link: "https://loopwire.app/" },
      { text: "Install", link: "/guide/install" },
      { text: "Basic Usage", link: "/guide/basic-usage" },
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
          { text: "Basic Usage", link: "/guide/basic-usage" },
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
          { text: "GitHub Actions Setup", link: "/developer/github-actions-setup" },
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
