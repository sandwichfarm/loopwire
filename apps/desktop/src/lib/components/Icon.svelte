<script module lang="ts">
  // Loopwire's own thin-stroke glyph set (clean-room, no reference assets).
  export type IconName =
    | "plus"
    | "minus"
    | "pencil"
    | "trash"
    | "eye"
    | "eye-off"
    | "chevron-right"
    | "chevron-down"
    | "speaker"
    | "speaker-off"
    | "mic"
    | "app"
    | "display"
    | "loop"
    | "gear"
    | "wave";
</script>

<script lang="ts">
  interface Props {
    readonly name: IconName;
    readonly size?: number;
  }

  const { name, size = 16 }: Props = $props();
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 16 16"
  fill="none"
  stroke="currentColor"
  stroke-width="1.5"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>
  {#if name === "plus"}
    <circle cx="8" cy="8" r="6.75" />
    <path d="M8 5.2v5.6M5.2 8h5.6" />
  {:else if name === "minus"}
    <path d="M3.5 8h9" />
  {:else if name === "pencil"}
    <path d="M3 13l.9-3.2 7.3-7.3a1.3 1.3 0 0 1 1.9 0l.4.4a1.3 1.3 0 0 1 0 1.9L6.2 12.1 3 13Z" />
  {:else if name === "trash"}
    <path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8a1.2 1.2 0 0 0 1.2 1.1h3.4a1.2 1.2 0 0 0 1.2-1.1l.6-8M6.7 7v4M9.3 7v4" />
  {:else if name === "eye"}
    <path d="M1.8 8s2.3-4 6.2-4 6.2 4 6.2 4-2.3 4-6.2 4-6.2-4-6.2-4Z" />
    <circle cx="8" cy="8" r="1.8" />
  {:else if name === "eye-off"}
    <path d="M1.8 8s2.3-4 6.2-4c1.2 0 2.3.4 3.2.9M14.2 8s-2.3 4-6.2 4c-1.2 0-2.3-.4-3.2-.9" />
    <path d="M2.5 13.5 13.5 2.5" />
  {:else if name === "chevron-right"}
    <path d="M6 4l4 4-4 4" />
  {:else if name === "chevron-down"}
    <path d="M4 6l4 4 4-4" />
  {:else if name === "speaker"}
    <path d="M2.5 6.2v3.6h2.4L8.6 13V3L4.9 6.2H2.5Z" />
    <path d="M10.8 5.8a3.2 3.2 0 0 1 0 4.4M12.6 4.2a5.6 5.6 0 0 1 0 7.6" />
  {:else if name === "speaker-off"}
    <path d="M2.5 6.2v3.6h2.4L8.6 13V3L4.9 6.2H2.5Z" />
    <path d="M10.7 6.3l3 3.4M13.7 6.3l-3 3.4" />
  {:else if name === "mic"}
    <rect x="6" y="2" width="4" height="7" rx="2" />
    <path d="M3.8 7.5a4.2 4.2 0 0 0 8.4 0M8 11.7V14" />
  {:else if name === "app"}
    <rect x="2.2" y="2.8" width="11.6" height="10.4" rx="1.5" />
    <path d="M2.2 5.6h11.6M4.2 4.2h.01M6 4.2h.01" />
  {:else if name === "display"}
    <rect x="2" y="3" width="12" height="8" rx="1.2" />
    <path d="M6 13.5h4M8 11v2.5" />
  {:else if name === "loop"}
    <path d="M5 4.5h5.5a3 3 0 0 1 0 6H5.5a3 3 0 0 1 0-6" />
    <path d="M7 2.5 5 4.5l2 2M9 8.5l2 2-2 2" />
  {:else if name === "gear"}
    <circle cx="8" cy="8" r="2.2" />
    <path
      d="M8 1.8v1.7M8 12.5v1.7M1.8 8h1.7M12.5 8h1.7M3.6 3.6l1.2 1.2M11.2 11.2l1.2 1.2M12.4 3.6l-1.2 1.2M4.8 11.2l-1.2 1.2"
    />
  {:else if name === "wave"}
    <path d="M1.8 8h1.6l1.4-3.4L7 11.4 8.8 5l1.4 4.6.9-1.6h3.1" />
  {/if}
</svg>
