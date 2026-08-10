# Release CI reliability

State: resolved
Type: task

## Goal

Ensure Windows-native Quick Tag notifications acknowledge their platform
message without waiting for a user-controlled Flutter dialog, so tagged
releases can complete their CI verification and publish artifacts.

## Acceptance

- Windows `activated` and `externalPaths` notifications return to the native
  caller before their Flutter UI workflow completes.
- Regression coverage holds an activation UI workflow open while asserting the
  platform message has already completed.
- The tray lifecycle test asserts the implemented close-to-tray behavior
  without coupling to an internal `switch` layout.
- The normal Windows Release build produces the Explorer bridge required by the
  installer and portable package.

## Comments

- 2026-08-10: The v0.2.0 GitHub release run identified three CI failures.
  Native activation acknowledgement was waiting on user-controlled dialogs, and
  the bridge target was omitted from Flutter's default CMake build graph.
