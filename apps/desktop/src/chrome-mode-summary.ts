export type ChromeMode = "native" | "custom";
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

export function describeChromeModeSummary(input: ChromeModeSummaryInput): ChromeModeSummary {
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
