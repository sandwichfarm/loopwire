<script lang="ts">
  import Icon from "./Icon.svelte";
</script>

<div class="empty">
  <span class="glyph" aria-hidden="true"><Icon name="loop" size={56} /></span>
  <p>Create your first virtual audio device by clicking <strong>New Virtual Device</strong>.</p>
</div>

<style>
  .empty {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--lw-space-4);
    color: var(--lw-text-secondary);
    text-align: center;
    padding: var(--lw-space-5);
  }

  .glyph {
    color: var(--lw-track);
  }

  p {
    font: var(--lw-text-empty);
    max-width: 320px;
    margin: 0;
  }

  strong {
    color: var(--lw-text-primary);
  }
</style>
