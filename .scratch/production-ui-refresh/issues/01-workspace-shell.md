# 01 - Modern responsive workspace shell

State: resolved
Type: task

Implement semantic theme tokens, the responsive expanded/icon navigation states, the context header, and the top-right command area without changing navigation semantics.

## Comments

- Preserve the dedicated Search page and top-right space switcher.
- Implemented 232px expanded navigation and 72px compact navigation using `LayoutBuilder`, with the active page preserved independently from navigation width.
- Added the modern context bar, top-right space/import commands, and centralized production theme tokens.
