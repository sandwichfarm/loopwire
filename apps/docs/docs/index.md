---
layout: page
---

<section class="lw-hero">
  <figure class="lw-hero-media">
    <img
      src="/product-screenshot.svg"
      alt="Loopwire desktop shell with saved configurations, backend prompt, route controls, outputs, and monitors."
    />
  </figure>
  <div class="lw-hero-copy">
    <p class="lw-kicker">Linux virtual audio routing</p>
    <h1>Loopwire</h1>
    <p class="lw-subline">
      A desktop-grade routing workspace for PipeWire and PulseAudio compatibility: build named mixes, switch them
      instantly, restore them on startup, and keep backend limits visible instead of buried in shell state.
    </p>
    <div class="lw-hero-row">
      <figure class="lw-install">
        <figcaption>Current source install</figcaption>
        <pre><code>git clone https://github.com/sandwichfarm/loopwire
cd loopwire
pnpm install
pnpm check</code></pre>
      </figure>
      <figure class="lw-install">
        <figcaption>Release-gated curl install</figcaption>
        <pre><code>curl -fsSL https://&lt;docs-host&gt;/install.sh \
  | sh
loopwire --background --mode preview</code></pre>
      </figure>
      <div class="lw-release-status" aria-label="Release status">
        <strong>v0.1.0 candidate</strong>
        <span>The curl path activates after signed public artifacts, Bunny deploy, and VM proof pass.</span>
      </div>
    </div>
    <div class="lw-actions">
      <a href="/guide/install">Install paths</a>
      <a class="secondary" href="/guide/start-on-boot">Start on boot</a>
      <a class="secondary" href="/guide/support-matrix">Support matrix</a>
    </div>
  </div>
</section>

<section class="lw-proof-strip" aria-label="Current proof status">
  <article>
    <span>Backends</span>
    <strong>PipeWire and PulseAudio paths</strong>
    <p>Read-only detection, guarded host adapters, and explicit route semantics.</p>
  </article>
  <article>
    <span>Desktop</span>
    <strong>Configurations restore</strong>
    <p>Named workspaces, monitor visibility, source/output/monitor pickers, and start-on-boot controls.</p>
  </article>
  <article>
    <span>Release</span>
    <strong>Candidate, not published</strong>
    <p>Installer, packaging, CI, and VM evidence gates exist; public artifacts still need release decisions.</p>
  </article>
</section>

<section class="lw-terminal-band" aria-label="Installer readiness">
  <div>
    <p class="lw-kicker">Release ceremony</p>
    <h2>Install paths are rehearsed before they are advertised.</h2>
  </div>
  <figure class="lw-install wide">
    <figcaption>Release readiness preflight</figcaption>
      <pre><code>git clone https://github.com/sandwichfarm/loopwire
cd loopwire
pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0
pnpm collect:evidence -- --output-dir .release-evidence/v0.1.0 --profile full --release-tag v0.1.0</code></pre>
  </figure>
</section>

<section class="lw-grid" aria-label="Core promises">
  <article>
    <h2>Real Backends</h2>
    <p>PipeWire first, with explicit compatibility paths for PulseAudio, JACK, and ALSA.</p>
  </article>
  <article>
    <h2>Instant Configs</h2>
    <p>Create, edit, import, export, and tune named routing states through a tested app-runtime transaction.</p>
  </article>
  <article>
    <h2>Desktop Native</h2>
    <p>Native chrome where it works, custom controls where a DE or WM needs help.</p>
  </article>
</section>
