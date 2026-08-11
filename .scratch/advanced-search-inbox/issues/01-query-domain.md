# 01 - Search metadata and query domain

State: resolved
Type: task

Add resource metadata and deterministic advanced-query evaluation.

## Acceptance

- Managed size and creation timestamps flow into tag-domain resources.
- Existing JSON state remains readable.
- Keyword, kind, size, date, AND, OR, and NOT filters compose predictably.
- Effective tags are calculated for an explicit space, not implicit UI state.

## Comments

- 2026-08-11: Resolved. Search metadata remains backward compatible, effective tags accept an explicit space ID, and composed metadata/tag filters are covered by controller tests.
