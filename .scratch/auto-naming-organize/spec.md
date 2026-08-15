# Auto naming template and manual organize (P1-5)

Design confirmed by the user on 2026-08-15: full scope (naming + archive), global template with import preview, manual batch organize only (never automatic on tagging).

## Auto naming (导入自动命名)

- Global preference `namingTemplate` (string, default `''` = keep original names). Placeholders: `{原名}` `{日期}` `{时间}` `{标签}` `{序号}`.
- Settings → 导入与标注: a template text field with placeholder help and a live example preview.
- Import dialog: when a template is set, a 按模板重命名 toggle (default ON) plus a preview line showing the first source's resulting name; turning it off imports with original names for that batch.
- Naming rule: apply per source with its own name, import date, the chosen tag names (joined by `、` or empty→`未标注`), and a 1-based batch index for `{序号}`. Keep the original file extension. Sanitize `\/:*?"<>|` to `-`. Result stays a normal file in the chosen target directory; existing name-conflict behavior (never overwrite) is unchanged.

## Manual organize (手动批量整理/归档)

- New tag action in the hierarchy result panel menu: 整理此标签的资源到目录.
- Rule: resources in the active space whose EFFECTIVE tags include the selected tag are moved (files preserved byte-for-byte) into a storage-root subdirectory named after the tag's path segments, e.g. `项目/设计` → `<存储根>/项目/设计/`. Resources already in place are skipped; name conflicts never overwrite — show a conflict summary and let the user cancel or skip conflicting items.
- Preview first: counts, target directory, conflicts; explicit confirm executes.
- This is a managed operation: the library updates managed paths in the same transaction, writes an operation log entry (new type `organizeMove`), and supports domain undo (API-level; no UI undo button per the unified-log decision).
- Consistency scanner must not report organize moves as external changes (paths updated in the same transaction, like other managed ops).

## Acceptance

- Domain tests: template rendering (placeholders, extension kept, sanitization, index, empty-tag fallback); preview counts/conflicts; organize move round-trip (bytes identical, DB paths updated, scan stays clean, undo restores); persistence of the template preference.
- Widget tests: settings field saves template; import dialog shows preview + toggle; tag menu opens the organize preview and executes.
- analyze 0; full suite green; Release build.
