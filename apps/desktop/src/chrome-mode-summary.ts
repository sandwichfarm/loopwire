export type ChromeMode = "auto" | "native" | "custom";
export type ResolvedChromeMode = "native" | "custom";
export type ChromeModeSummaryTone = "native" | "fallback" | "preview";

export interface ChromeModeSummaryInput {
  readonly mode: ChromeMode;
  readonly desktopRuntimeAvailable: boolean;
}

export interface ChromeModeSummary {
  readonly tone: ChromeModeSummaryTone;
  readonly title: string;
  readonly message: string;
}

export function resolveChromeMode(mode: ChromeMode, desktopRuntimeAvailable: boolean): ResolvedChromeMode {
  if (mode === "auto") {
    return desktopRuntimeAvailable ? "native" : "custom";
  }

  return mode;
}

export function describeChromeModeSummary(input: ChromeModeSummaryInput): ChromeModeSummary {
  if (input.mode === "auto") {
    const resolved = resolveChromeMode(input.mode, input.desktopRuntimeAvailable);

    if (resolved === "custom") {
      return {
        tone: "preview",
        title: "Auto fallback controls",
        message: "Loopwire shows fallback controls when system window decorations cannot be managed."
      };
    }

    return {
      tone: "native",
      title: "Auto system chrome",
      message: "Loopwire uses desktop or window-manager decorations when decoration control is available."
    };
  }

  if (!input.desktopRuntimeAvailable) {
    return {
      tone: "preview",
      title: "Preview window controls",
      message: "Browser preview can show the fallback controls, but only the desktop shell can change decorations."
    };
  }

  if (input.mode === "custom") {
    return {
      tone: "fallback",
      title: "Loopwire fallback controls",
      message: "Loopwire requests an undecorated window and provides drag, minimize, maximize, and close controls."
    };
  }

  return {
    tone: "native",
    title: "System chrome preferred",
    message: "Loopwire uses the desktop environment or window manager decorations when they are available."
  };
}
