import { describe, expect, it } from "vitest";
import { describeChromeModeSummary } from "./chrome-mode-summary";

describe("describeChromeModeSummary", () => {
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
