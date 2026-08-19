import '../data/local_store.dart';
import '../platform/windows_close_behavior.dart';
import '../platform/windows_floating_drop_target.dart';

/// Applies the persisted Windows integration preferences to the native side:
/// the auto-start registration and the floating drop target (position first,
/// then enable/disable). Shared by the home screen startup sync and the
/// first-run setup wizard so a wizard choice takes effect immediately.
///
/// Returns the floating-target apply result (false when the native side
/// reported a failure, null when the plugin is unavailable) so callers can
/// surface a warning.
Future<bool?> applyWindowsIntegrationPreferences({
  required UserPreferences preferences,
  required WindowsCloseBehavior closeBehavior,
  required WindowsFloatingDropTarget floatingDropTarget,
}) async {
  await closeBehavior.setAutoStart(preferences.autoStartEnabled);
  final x = preferences.floatingTargetX;
  final y = preferences.floatingTargetY;
  if (x != null && y != null) {
    await floatingDropTarget.setPosition(x, y);
  }
  return floatingDropTarget.setEnabled(preferences.floatingDropTargetEnabled);
}
