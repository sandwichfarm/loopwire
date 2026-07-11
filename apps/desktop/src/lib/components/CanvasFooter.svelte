<script lang="ts">
  import Button from "./Button.svelte";

  interface Props {
    readonly canDelete: boolean;
    readonly monitorsHidden: boolean;
    readonly onDelete: () => void;
    readonly onToggleMonitors: () => void;
  }

  const { canDelete, monitorsHidden, onDelete, onToggleMonitors }: Props = $props();
</script>

<footer class="canvas-footer">
  <Button label="Delete" icon="trash" disabled={!canDelete} onClick={onDelete} />
  <Button
    label={monitorsHidden ? "Show Monitors" : "Hide Monitors"}
    icon={monitorsHidden ? "eye-off" : "eye"}
    onClick={onToggleMonitors}
  />
</footer>

<style>
  .canvas-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: var(--lw-footer-height);
    padding: 0 12px;
    border-top: 1px solid var(--lw-hairline);
    background: var(--lw-canvas-bg);
    flex: none;
  }
</style>
