# Release versioning

TAGTAG releases use `MAJOR.MINOR.PATCH` and Git tags use `vMAJOR.MINOR.PATCH`.

## Policy

- `MAJOR` changes only for incompatible API changes or major architecture changes.
- `MINOR` changes for backward-compatible new features.
- `PATCH` changes only for backward-compatible bug fixes and contains no new features.
- `0.y.z` denotes the current unstable development phase. `1.0.0` requires an explicit stable-release decision.
- Published Git tags and GitHub Releases are immutable historical artifacts. Incorrect historical increments are documented but not rewritten.
- The version in `pubspec.yaml` must match the release tag, ignoring the leading `v` and Flutter build suffix.

## Current baseline

The latest successful release is `v0.7.0`. Therefore:

- the next bug-fix-only release is `v0.7.1`;
- the next backward-compatible feature release is `v0.8.0`.
