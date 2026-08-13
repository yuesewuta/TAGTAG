# 04 - Exact parity verification

State: resolved
Type: task
Blocked by: 02, 03

Compare prototype and Flutter screenshots at every target size, validate interactions one by one, run all existing tests, and build the Windows Release artifact.

- 2026-08-12: static gates green (analyze 0, tests 96/96, Release build + plugin junctions verified). Multi-size visual capture pass started but interrupted; remaining: complete 1440/1024/960/768/375/812x375 screenshot comparison.
- Resolved 2026-08-12: user manually verified the parity UI in the Release window; follow-up interaction changes (merged import entry, reparent dialog, expansion controls, drag-to-reparent) verified by 100/100 tests and Release builds.
