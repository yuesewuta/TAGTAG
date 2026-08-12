# TAGTAG Workspace Override

This page-level override replaces any landing-page or mobile-SaaS patterns in `MASTER.md` for the desktop workspace prototype.

## Product Pattern

- Type: Windows desktop file manager and local-first productivity tool.
- Structure: persistent navigation, contextual command bar, dense resource table, optional details inspector.
- Density: compact but readable; 36-44px rows, 8-16px internal spacing, stable columns.
- Style: flat minimalism with subtle tonal layers, clear borders, and restrained elevation only for transient windows.

## Color

- Primary action and focus: `#285CC4` / hover `#1F4DA8`.
- Foreground: `#18202B`; secondary text: `#5D6878`.
- Canvas: `#F5F7FA`; navigation: `#EEF1F5`; surface: `#FFFFFF`.
- Border: `#DDE2E9`; selected row: `#EAF1FF`.
- Folder/accent: `#C47A16`; success: `#1F7A55`; warning: `#B65D18`; destructive: `#C43B43`.
- Tags use a controlled multi-hue palette and never rely on hue alone: every tag includes a text label and optional source icon.

## Typography

- Use local Windows/system fonts: `Segoe UI Variable`, `Segoe UI`, `Noto Sans SC`, sans-serif.
- Type scale: 12, 13, 14, 16, 20, 24. Body is 14px for desktop density; no viewport-scaled type.
- Use weight and spacing for hierarchy. Letter spacing remains zero.

## Layout

- `>= 1280px`: 232px navigation + fluid table + 300px inspector.
- `960-1279px`: 72px navigation rail + fluid table; inspector becomes an overlay drawer.
- `< 960px`: compact header and hidden navigation drawer; resource table removes low-priority columns.
- `< 680px`: rows become stacked resource summaries and task dialogs become full-height sheets.
- Keep title bar, command bar, table header, rows, and icon controls at stable heights to avoid resize jitter.

## Window Hierarchy

- Main workspace owns browse, search, selection, and context.
- Quick Tag is a command palette optimized for keyboard use and a single decision.
- Import is a larger task window with source, destination, labels, and copy/move confirmation visible together.
- Settings is a system window for defaults, integrations, storage health, backup, and appearance. It does not duplicate daily commands.
- Consistency alerts and operation history live in a system-status center reached from the persistent health indicator.

## Motion

- 150ms hover/focus feedback; 180-220ms drawers and dialogs; 120ms selected-row state.
- Animate only `opacity` and `transform`; never animate table dimensions during resize.
- Dense resource rows do not use overshoot or large stagger effects.
- Respect `prefers-reduced-motion` and preserve immediate focus movement.

## Iconography

- Use one outline icon family consistently (Lucide or Phosphor), 18-20px at 1.5-2px stroke.
- Icon-only buttons require accessible labels and tooltips.
- Tags use swatches; warnings, inherited tags, and reused tag entities include distinct icons or borders in addition to color.

