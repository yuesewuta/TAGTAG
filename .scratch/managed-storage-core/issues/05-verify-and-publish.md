# 05 - Verify and publish

State: resolved
Type: task
Blocked by: 01, 02, 03, 04

Run formatting, analysis, tests, Windows build, and UI checks. Inspect the requested GitHub remote, establish a non-destructive Git baseline, and push without force.

## Acceptance

- All automated checks and Windows build pass.
- Remote history is inspected before integrating or pushing.
- The pushed branch contains the verified milestone state and no generated build output.

## Comments

- 2026-08-09: `flutter analyze --no-pub` passed with 0 issues; all 25 tests passed.
- 2026-08-09: Windows Release build passed and produced `build/windows/x64/runner/Release/tagtag.exe`.
- 2026-08-09: Developer Mode is disabled locally; generated plugin paths were represented by workspace-only directory junctions for the build and remain ignored.
- 2026-08-09: Created `codex/managed-storage-core`, preserved `origin/main` as an ancestor through a non-destructive unrelated-history merge, and pushed without force.
- 2026-08-09: Rebuilt the Windows Release after the file-open and navigation changes; packaging, folder-dialog, and single-instance smoke checks all passed.
- 2026-08-09: Settings persistence passed a real save/close/restart check, and the user's original expanded-navigation preference was restored after verification.
- 2026-08-09: Stage 11 passed 37 Flutter tests, 0 analyzer issues, Windows Release build, all three EXE smoke checks, and 1280x720/960x720 `PrintWindow` verification.
