# 02 - Inheritance controls and source display

State: resolved
Type: task
Blocked by: 01

Extend the existing single-window Quick Tag flow with an explicit folder inheritance control and show inherited tag sources in resource rows.

## Acceptance

- The inheritance control is shown only when exactly one folder is selected.
- The control defaults to the selected folder's current rule state for the chosen tag.
- Confirming can enable or disable the rule while retaining the direct tag.
- Effective tag chips visually distinguish inherited-only tags and name their source folder in the tooltip.

## Comments

- 2026-08-11: Resolved. Quick Tag uses one dialog with tag selection and a single-folder inheritance switch. Resource rows show effective tags, an inheritance icon, and source-folder tooltips while the clear command remains limited to direct tags.
