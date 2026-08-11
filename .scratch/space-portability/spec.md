# Space package and template portability

A space export package migrates one tag space with its metadata, history, resource references, resource bytes, manifest, and integrity hashes. A space template carries only reusable tag structure and configuration.

## Acceptance

- A versioned manifest identifies the package kind and records SHA-256 for every entry.
- Space packages include space metadata, tags, placements, membership, assignments, inheritance rules, usage history, and referenced resource bytes.
- Each managed resource entity is stored once per package even when multiple tags reference it.
- Different managed entities remain separate even when their bytes are identical.
- Package import verifies paths, manifest entries, hashes, metadata references, and resource conflicts before committing.
- Existing stable resource IDs are reused only when they identify the same existing managed resource; imported new entities preserve controlled IDs.
- Templates include tag structure and configuration only, never resource records or bytes.
- Space portability remains separate from global backup and restore.
