# Production UI exact prototype parity

The production Flutter client must reproduce `prototypes/ui-refresh/index.html`, `styles.css`, and `app.js` as the authoritative UI and interaction specification. Existing production capabilities remain the data/action backend, but their presentation must use the prototype's window hierarchy, layout, component geometry, visual tokens, responsive behavior, and interaction model.

## Acceptance

- The 1440px desktop workspace reproduces the prototype's 32px window bar and `232px / fluid / 300px` navigation, workspace, and inspector columns.
- The left navigation reproduces the brand block, space switcher/menu, six destinations, Quick Tag command, library health toggle, settings entry, selected state, iconography, spacing, and bottom grouping.
- The resource workspace reproduces the page header, Import-only top action, command bar, query field, filter/sort controls, dense resource table, selection states, tag chips, inline row commands, and lower status line.
- The right inspector reproduces empty/selected states, resource identity, metadata, direct/effective tags, and available resource commands.
- Tag hierarchy reproduces the split tree/results layout, path and resource counts, selected tag state, relationship editor, parent options with cycle prevention, and immediate hierarchy updates.
- Quick Tag, import, settings, library health, and operation log reproduce the prototype's modal/drawer hierarchy, dimensions, categories, controls, keyboard dismissal, and state transitions.
- Space switching updates every prototype-defined visible context and preserves two selectable demo/real space options when the production state provides them.
- The prototype's light/dark appearance, density behavior, focus states, hover/pressed feedback, keyboard shortcuts, drag-import state, and reduced-motion behavior are reproduced where supported by Flutter/Windows.
- At 1440, 1024, 960, 768, 375, and 812x375, the client follows the prototype's exact responsive rules with no overlap or horizontal overflow.
- The supplied `LOGO.png` is bundled and displayed in the prototype-defined brand and window identity positions without distortion.
- Existing domain operations, managed-file safety, logging, undo, import, tagging, hierarchy, and storage behavior remain functional behind the new UI.
- Static analysis, UI contract tests, existing full regression tests, and Windows Release build pass.

## Superseded interpretation

The earlier production refresh intentionally omitted the prototype inspector and global workspace query while retaining the old client command structure. That interpretation does not meet this specification and is superseded by the user's explicit exact-parity requirement.
