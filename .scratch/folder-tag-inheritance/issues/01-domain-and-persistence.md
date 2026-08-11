# 01 - Dynamic inheritance domain and persistence

State: resolved
Type: task

Add a persisted folder/tag inheritance rule and compute effective tags from current managed paths.

## Acceptance

- Legacy state without inheritance rules still loads.
- Rules use stable folder resource and tag entity IDs.
- Effective tags preserve direct and inherited source information.
- Inbox and tag hierarchy queries use effective tags.
- Deleting a tag, clearing source tags, or removing the source folder cleans up its rules.

## Comments

- 2026-08-11: Resolved. State version 3 persists stable folder/tag rules with legacy fallback. Effective tags are path-dynamic, preserve direct and inherited sources, drive inbox and hierarchy queries, and ignore dangling rules.
