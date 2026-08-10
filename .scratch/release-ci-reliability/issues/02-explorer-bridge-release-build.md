# 02 - Explorer bridge release build

State: resolved
Type: task

Make the primary Windows application target depend on the Explorer bridge so
the normal Flutter Release build always contains the executable registered by
the installer.

## Comments

- 2026-08-10: The primary runner target now depends on
  `tagtag_explorer_bridge`, ensuring Flutter's normal Release build stages the
  bridge binary for portable and installer packaging.
