import { describe, expect, it } from "vitest";
import { describeChromeModeSummary, resolveChromeMode } from "./chrome-mode-summary";

describe("resolveChromeMode", () => {
  it("prefers system chrome in the desktop shell when mode is automatic", () => {
    expect(resolveChromeMode("auto", true)).toBe("native");
  });

  it("falls back to Loopwire controls when decoration control is unavailable", () => {
    expect(resolveChromeMode("auto", false)).toBe("custom");
  });

  it("honors explicit chrome choices", () => {
    expect(resolveChromeMode("native", false)).toBe("native");
    expect(resolveChromeMode("custom", true)).toBe("custom");
  });
});

describe("describeChromeModeSummary", () => {
  it("describes automatic chrome selection in the desktop shell", () => {
    expect(describeChromeModeSummary({ mode: "auto", desktopRuntimeAvailable: true })).toEqual({
      tone: "native",
      title: "Auto system chrome",
      message: "Loopwire uses desktop or window-manager decorations when decoration control is available."
    });
  });

  it("describes automatic fallback controls when decoration control is unavailable", () => {
    expect(describeChromeModeSummary({ mode: "auto", desktopRuntimeAvailable: false })).toEqual({
      tone: "preview",
      title: "Auto fallback controls",
      message: "Loopwire shows fallback controls when system window decorations cannot be managed."
    });
  });

  it("describes the native-first chrome policy in the desktop shell", () => {
    expect(describeChromeModeSummary({ mode: "native", desktopRuntimeAvailable: true })).toEqual({
      tone: "native",
      title: "System chrome preferred",
      message: "Loopwire uses the desktop environment or window manager decorations when they are available."
    });
  });

  it("describes Loopwire-owned fallback controls when custom chrome is selected", () => {
    expect(describeChromeModeSummary({ mode: "custom", desktopRuntimeAvailable: true })).toEqual({
      tone: "fallback",
      title: "Loopwire fallback controls",
      message: "Loopwire requests an undecorated window and provides drag, minimize, maximize, and close controls."
    });
  });

  it("keeps browser preview honest about decoration changes", () => {
    expect(describeChromeModeSummary({ mode: "custom", desktopRuntimeAvailable: false })).toEqual({
      tone: "preview",
      title: "Preview window controls",
      message: "Browser preview can show the fallback controls, but only the desktop shell can change decorations."
    });
  });
});
