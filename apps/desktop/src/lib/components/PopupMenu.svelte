<script module lang="ts">
  import type { IconName } from "./Icon.svelte";

  export interface MenuItem {
    readonly id: string;
    readonly label: string;
    readonly icon?: IconName;
    readonly detail?: string;
    readonly disabled?: boolean;
  }

  export interface MenuSection {
    readonly title?: string;
    readonly items: readonly MenuItem[];
  }
</script>

<script lang="ts">
  import { tick } from "svelte";
  import Icon from "./Icon.svelte";

  interface Props {
    readonly sections: readonly MenuSection[];
    readonly anchor: HTMLElement;
    readonly label: string;
    readonly emptyMessage?: string;
    readonly onPick: (id: string) => void;
    readonly onClose: () => void;
  }

  const { sections, anchor, label, emptyMessage, onPick, onClose }: Props = $props();

  let menu: HTMLDivElement | undefined = $state();
  let typeahead = "";
  let typeaheadTimer: ReturnType<typeof setTimeout> | undefined;

  const flatItems = $derived(sections.flatMap((section) => section.items).filter((item) => !item.disabled));
  const position = $derived.by(() => {
    const rect = anchor.getBoundingClientRect();
    return { x: rect.left, y: rect.bottom + 4 };
  });

  $effect(() => {
    void tick().then(() => {
      const first = menu?.querySelector<HTMLButtonElement>("button.item:not(:disabled)");
      first?.focus();
      clampIntoViewport();
    });
  });

  function clampIntoViewport(): void {
    if (!menu) {
      return;
    }

    const rect = menu.getBoundingClientRect();
    const overflowY = rect.bottom - window.innerHeight + 8;
    const overflowX = rect.right - window.innerWidth + 8;

    if (overflowY > 0) {
      menu.style.top = `${Math.max(8, position.y - overflowY)}px`;
    }

    if (overflowX > 0) {
      menu.style.left = `${Math.max(8, position.x - overflowX)}px`;
    }
  }

  function focusedIndex(): number {
    const buttons = allButtons();
    return buttons.findIndex((button) => button === document.activeElement);
  }

  function allButtons(): HTMLButtonElement[] {
    return menu ? [...menu.querySelectorAll<HTMLButtonElement>("button.item:not(:disabled)")] : [];
  }

  function moveFocus(delta: number): void {
    const buttons = allButtons();

    if (buttons.length === 0) {
      return;
    }

    const index = focusedIndex();
    const next = index === -1 ? 0 : (index + delta + buttons.length) % buttons.length;
    buttons[next]?.focus();
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      moveFocus(1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      moveFocus(-1);
    } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey) {
      typeahead += event.key.toLowerCase();
      clearTimeout(typeaheadTimer);
      typeaheadTimer = setTimeout(() => {
        typeahead = "";
      }, 600);

      const match = flatItems.find((item) => item.label.toLowerCase().startsWith(typeahead));
      if (match) {
        const buttons = allButtons();
        buttons.find((button) => button.dataset.itemId === match.id)?.focus();
      }
    }
  }
</script>

<div
  class="backdrop"
  onclick={onClose}
  onkeydown={(event) => {
    if (event.key === "Escape") {
      onClose();
    }
  }}
  role="presentation"
></div>
<div
  class="menu"
  role="menu"
  aria-label={label}
  tabindex="-1"
  bind:this={menu}
  style:left="{position.x}px"
  style:top="{position.y}px"
  onkeydown={handleKeydown}
>
  {#each sections as section, sectionIndex (sectionIndex)}
    {#if section.items.length > 0}
      {#if section.title}
        <div class="section-title" role="presentation">{section.title}</div>
      {/if}
      {#each section.items as item (item.id)}
        <button
          type="button"
          class="item"
          role="menuitem"
          data-item-id={item.id}
          disabled={item.disabled}
          onclick={() => onPick(item.id)}
        >
          {#if item.icon}
            <Icon name={item.icon} size={14} />
          {/if}
          <span class="item-label">{item.label}</span>
          {#if item.detail}
            <span class="item-detail">{item.detail}</span>
          {/if}
        </button>
      {/each}
      {#if sectionIndex < sections.length - 1}
        <div class="separator" role="separator"></div>
      {/if}
    {/if}
  {/each}
  {#if flatItems.length === 0}
    <div class="empty">{emptyMessage ?? "Nothing available to add."}</div>
  {/if}
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 40;
  }

  .menu {
    position: fixed;
    z-index: 50;
    min-width: 220px;
    max-width: 320px;
    max-height: 60vh;
    overflow-y: auto;
    background: var(--lw-menu-bg);
    border: 1px solid var(--lw-hairline);
    border-radius: var(--lw-menu-radius);
    box-shadow: var(--lw-menu-shadow);
    padding: 4px;
    display: flex;
    flex-direction: column;
  }

  .section-title {
    font: var(--lw-text-subtitle);
    color: var(--lw-text-dim);
    padding: 4px 8px 2px;
  }

  .separator {
    height: 1px;
    background: var(--lw-hairline);
    margin: 4px 6px;
  }

  .item {
    display: flex;
    align-items: center;
    gap: var(--lw-space-2);
    min-height: var(--lw-menu-item-height);
    padding: 2px 8px;
    border: none;
    border-radius: 5px;
    background: transparent;
    color: var(--lw-text-primary);
    font: var(--lw-text-body);
    cursor: pointer;
    text-align: left;
  }

  .item:hover:not(:disabled),
  .item:focus-visible {
    background: var(--lw-selection-tint);
    outline: none;
  }

  .item:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .item-label {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .item-detail {
    font: var(--lw-text-subtitle);
    color: var(--lw-text-dim);
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .empty {
    padding: 8px 10px;
    font: var(--lw-text-body);
    color: var(--lw-text-secondary);
  }
</style>
