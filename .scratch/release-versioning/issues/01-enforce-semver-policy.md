# 01 - Enforce SemVer policy

State: resolved
Type: task

Document the confirmed release policy and prevent a release tag from disagreeing with the project version.

## Acceptance

- Project and release documentation define the confirmed `MAJOR.MINOR.PATCH` meanings.
- The project remains on a pre-`1.0.0` version until stabilization is explicit.
- Tag releases reject malformed tags and tags that differ from `pubspec.yaml`.
- Existing published tags and Releases are not rewritten.

## Comments

- 2026-08-11: Resolved. The workflow validates tag syntax and exact agreement with `pubspec.yaml`; release packaging tests cover the pre-1.0 project baseline and workflow guard.
