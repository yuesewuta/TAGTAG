# 02 - Resource, hierarchy, and settings surfaces

State: resolved
Type: task
Blocked by: 01

Refactor the resource table, split hierarchy workspace, and categorized settings dialog while preserving direct resource actions and existing domain commands.

## Comments

- Do not add the prototype inspector to production.
- Added the modern resource header, stable table rows, direct actions, and status bar without an inspector or duplicate global search.
- Replaced the embedded hierarchy list with a recursive tree and selected-tag result pane while preserving merge/split actions.
- Rebuilt Settings as a categorized desktop dialog exposing only current general, storage, and Windows integration surfaces.
