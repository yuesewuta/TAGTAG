# TAGTAG UI Refresh Prototype

Open `index.html` directly in a browser. The prototype is isolated from the Flutter application and has no build or network dependency.

## Covered Scenes

- Main resource workspace with persistent navigation, contextual commands, dense table, selection, and details inspector.
- Tag hierarchy as a split tree/result workspace that distinguishes tag entities, placements, and reused unique tags.
- Quick Tag as a focused keyboard-friendly child window.
- Import and tag as a larger task window with source, destination, tags, and copy/move effects visible together.
- Settings as the home for persistent defaults, storage/backup, Windows integrations, and appearance.
- System status center for consistency, storage health, backup, operation history, and undo.
- Responsive states for expanded desktop, navigation rail, drawer navigation, reduced table columns, and narrow-window sheets.

## Prototype Interactions

- Switch the primary views from the left navigation.
- Search and select resources, open the inspector, and launch Quick Tag.
- Open import, settings, and the system status center.
- Switch settings categories, theme, density, and import mode.
- Use `Ctrl+Shift+T` for Quick Tag, `Ctrl+K` for search, and `Esc` to close transient surfaces.
- Drag a file over the page to preview the import drop state.

