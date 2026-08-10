# 01 - Native Quick Tag acknowledgement

State: resolved
Type: task

Correct the Windows Quick Tag channel so a native activation is acknowledged
before its Flutter dialog workflow completes. Add regression coverage and
publish the corrected Windows release.

## Comments

- 2026-08-10: Native method-channel events now acknowledge before a
  user-controlled Flutter dialog completes; the regression test keeps that
  dialog workflow pending while asserting the platform response has returned.
