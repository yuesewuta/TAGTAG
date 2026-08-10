# 01 - Native Quick Tag acknowledgement

State: resolved
Type: task

Correct the Windows Quick Tag channel so a native activation is acknowledged
before its Flutter dialog workflow completes. Add regression coverage and
publish the corrected Windows release.

## Comments

- 2026-08-10: Native method-channel events now acknowledge before a
  user-controlled Flutter dialog completes. The app-initialization tests cover
  selected-resource and external-resource dialog activation through the real
  channel callback path.
- 2026-08-10: The Explorer activation test now waits for its asynchronous
  filesystem validation to create the import dialog after the native message
  has been acknowledged.
- 2026-08-10: The selected-resource activation test now waits for its dialog
  instead of using `pumpAndSettle`, because the home screen owns a periodic
  consistency scan. A clean Windows Release build also corrected the Explorer
  bridge Windows-header include order and the current Flutter MethodCall
  pointer API used by the floating drop target channel.
