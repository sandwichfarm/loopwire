import { gsap } from "gsap";

const palettes: Record<string, { background: string; accent: string }> = {
  automatic: { background: "#efece4", accent: "#176653" },
  arch: { background: "#e6edf0", accent: "#24617c" },
  ubuntu: { background: "#f0e7df", accent: "#974831" },
  debian: { background: "#eee5e5", accent: "#913f56" },
  fedora: { background: "#e5eaf1", accent: "#365c90" },
  opensuse: { background: "#e8ece1", accent: "#4b673b" },
  nix: { background: "#e7eded", accent: "#3d6771" },
  portable: { background: "#f0eadc", accent: "#7b6031" },
  source: { background: "#ece8ef", accent: "#695184" },
};

interface FieldState {
  width: number;
  height: number;
  pointer: { x: number; y: number; strength: number };
  pulse: { progress: number; origin: number; copy: boolean };
}

function drawField(context: CanvasRenderingContext2D, state: FieldState, accent: string) {
  const { width, height, pointer, pulse } = state;
  const envelope = Math.sin(pulse.progress * Math.PI);
  const radius = Math.min(width * 0.34, 320);
  context.clearRect(0, 0, width, height);
  context.lineWidth = 0.85;

  for (let line = 0; line < 24; line += 1) {
    const lane = (line % 12) - 5.5;
    const braid = line < 12 ? 1 : -1;
    context.strokeStyle = line % 4 === 0 ? "#283b34" : accent;
    context.globalAlpha = 0.12 + (line % 3) * 0.025 + (pulse.copy ? envelope * 0.08 : 0);
    context.beginPath();

    for (let point = 0; point < 72; point += 1) {
      const t = point / 71;
      let x = width * (-0.06 + t * 1.14);
      let y = height * (1.12 - 0.62 * t - 0.1 * Math.sin(t * Math.PI * 2));
      y += braid * height * 0.095 * Math.sin(t * Math.PI * 1.65);
      y += lane * Math.min(6, height * 0.006) * (0.45 + 0.7 * Math.sin(t * Math.PI));
      y += Math.sin(t * 18 + line * 0.25) * 2.4;

      const dx = pointer.x - x;
      const dy = pointer.y - y;
      const attraction = Math.exp(-(dx * dx + dy * dy) / (radius * radius)) * pointer.strength;
      x += dx * attraction * 0.045;
      y += dy * attraction * 0.075;
      const distance = pulse.copy ? t - pulse.progress : Math.abs(t - pulse.origin) - pulse.progress;
      y += Math.exp(-distance * distance * 110) * envelope * (pulse.copy ? 28 : 17) * braid;

      if (point === 0) context.moveTo(x, y);
      else context.lineTo(x, y);
    }
    context.stroke();
  }
  context.globalAlpha = 1;
}

/** Owns decorative canvas motion and the selected install palette; never intercepts input. */
export function createSignalField(canvas: HTMLCanvasElement) {
  const context = canvas.getContext("2d");
  const root = document.documentElement;
  const preference = window.matchMedia("(prefers-reduced-motion: reduce)");
  const originalBackground = root.style.getPropertyValue("--page-bg");
  const originalAccent = root.style.getPropertyValue("--accent");
  const colors = { ...palettes.automatic };
  const state: FieldState = {
    width: window.innerWidth,
    height: window.innerHeight,
    pointer: { x: window.innerWidth * 0.7, y: window.innerHeight * 0.7, strength: 0 },
    pulse: { progress: 1, origin: 0.5, copy: false },
  };
  let selected = "automatic";
  let destroyed = false;
  let resizePending = true;
  let frame = 0;
  let pointerTweens: ReturnType<typeof gsap.quickTo>[] = [];
  const canAnimate = () => !destroyed && !preference.matches && !document.hidden;

  function requestDraw() {
    if (destroyed || document.hidden || frame || !context) return;
    frame = window.requestAnimationFrame(() => {
      frame = 0;
      if (resizePending) {
        state.width = window.innerWidth;
        state.height = window.innerHeight;
        const ratio = Math.min(window.devicePixelRatio || 1, 1.5);
        canvas.width = Math.round(state.width * ratio);
        canvas.height = Math.round(state.height * ratio);
        context.setTransform(ratio, 0, 0, ratio, 0, 0);
        resizePending = false;
      }
      drawField(context, state, colors.accent);
    });
  }

  function paintPalette() {
    root.style.setProperty("--page-bg", colors.background);
    root.style.setProperty("--accent", colors.accent);
    requestDraw();
  }

  function select(id: string) {
    if (destroyed) return;
    selected = Object.hasOwn(palettes, id) ? id : "automatic";
    canvas.dataset.palette = selected;
    gsap.killTweensOf(colors);
    if (canAnimate()) {
      gsap.to(colors, { ...palettes[selected], duration: 0.8, ease: "power2.inOut", onUpdate: paintPalette });
    } else {
      Object.assign(colors, palettes[selected]);
      paintPalette();
    }
  }

  function stopMotion() {
    pointerTweens.forEach((move) => move.tween.kill());
    pointerTweens = [];
    gsap.killTweensOf(state.pulse);
    state.pointer.strength = 0;
    state.pulse.progress = 1;
    if (frame) window.cancelAnimationFrame(frame);
    frame = 0;
  }

  function refreshMotion() {
    stopMotion();
    gsap.killTweensOf(colors);
    Object.assign(colors, palettes[selected]);
    canvas.dataset.motion = preference.matches ? "reduced" : document.hidden ? "paused" : "interactive";
    if (canAnimate() && context) {
      pointerTweens = ["x", "y", "strength"].map((property) =>
        gsap.quickTo(state.pointer, property, { duration: 0.7, ease: "power3.out", onUpdate: requestDraw }));
    }
    paintPalette();
  }

  function pointerMove(event: PointerEvent) {
    if (!canAnimate() || event.pointerType === "touch") return;
    pointerTweens[0]?.(event.clientX);
    pointerTweens[1]?.(event.clientY);
    pointerTweens[2]?.(1);
  }

  function pointerLeave() {
    if (canAnimate()) pointerTweens[2]?.(0);
  }

  function pulse(copy: boolean, origin = 0.5) {
    if (!canAnimate() || !context) return;
    gsap.killTweensOf(state.pulse);
    Object.assign(state.pulse, { progress: 0, origin, copy });
    gsap.to(state.pulse, { progress: 1, duration: copy ? 1.15 : 0.85, ease: "none", onUpdate: requestDraw });
  }

  function click(event: MouseEvent) {
    pulse(false, event.detail === 0 ? 0.5 : event.clientX / Math.max(state.width, 1));
  }

  function resize() {
    resizePending = true;
    requestDraw();
  }

  window.addEventListener("pointermove", pointerMove, { passive: true });
  document.documentElement.addEventListener("pointerleave", pointerLeave);
  window.addEventListener("blur", pointerLeave);
  window.addEventListener("click", click, { passive: true, capture: true });
  window.addEventListener("resize", resize, { passive: true });
  document.addEventListener("visibilitychange", refreshMotion);
  preference.addEventListener("change", refreshMotion);
  canvas.dataset.palette = selected;
  refreshMotion();

  return {
    select,
    copied: () => pulse(true),
    destroy() {
      if (destroyed) return;
      destroyed = true;
      stopMotion();
      gsap.killTweensOf(colors);
      window.removeEventListener("pointermove", pointerMove);
      document.documentElement.removeEventListener("pointerleave", pointerLeave);
      window.removeEventListener("blur", pointerLeave);
      window.removeEventListener("click", click, true);
      window.removeEventListener("resize", resize);
      document.removeEventListener("visibilitychange", refreshMotion);
      preference.removeEventListener("change", refreshMotion);
      root.style.setProperty("--page-bg", originalBackground);
      root.style.setProperty("--accent", originalAccent);
      context?.clearRect(0, 0, state.width, state.height);
      delete canvas.dataset.palette;
      delete canvas.dataset.motion;
    },
  };
}
