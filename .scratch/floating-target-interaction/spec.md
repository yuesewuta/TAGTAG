# Floating drop target: drag, edge snap, proximity glow

## Current state

The floating drop target is a 64x64 `WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE` popup (`windows/runner/flutter_window.cpp`) painted via `UpdateLayeredWindow` with the app icon at per-pixel alpha. It accepts `WM_DROPFILES` and activates Quick Tag on left-click. It appears at a fixed position (bottom-right) when enabled.

## Requirements (user)

1. **Draggable**: hold and drag the ball anywhere; click (no drag) still activates Quick Tag.
2. **Edge snap**: on release, slide-snap to the nearest left/right edge of the current monitor's work area. Snapped state docks the ball half off-screen (roughly one third visible); hovering a snapped ball slides it fully out; leaving slides it back.
3. **Proximity accept effect**: when the user drags something (left button held) near the ball, the ball shows a "ready to accept" animation (pulsing glow ring + slide out if snapped). Works in both full and snapped states.

## Architecture

Native (`windows/runner/flutter_window.cpp/.h`), no Dart business logic:

- **Drag**: `WM_LBUTTONDOWN` → `SetCapture`, record cursor-to-window offset, `dragging_ = false`; `WM_MOUSEMOVE` while captured → if moved > 4px set `dragging_ = true` and `SetWindowPos`; `WM_LBUTTONUP` → `ReleaseCapture`; if `!dragging_` → existing Quick Tag activation; else begin snap animation.
- **Snap**: `MonitorFromWindow` + `GetMonitorInfo` for the work area; target x = left edge (ball half off: `workLeft - size/3`) or right edge (`workRight - size*2/3`), keep y clamped inside work area; animate with `WM_TIMER` (~16ms steps, ease-out cubic over ~180ms), then set `snapped_ = Left/Right/None`.
- **Hover expansion**: `TrackMouseEvent` for `WM_MOUSELEAVE`; when snapped and hovered → slide to fully visible (same timer animation); on leave (and not mid-drag) → slide back.
- **Proximity glow**: install a `WH_MOUSE_LL` hook while the target is enabled (uninstall on disable/destroy). The hook only does `GetCursorPos` + hit-test against an inflated ball rect (~+64px) with `GetKeyState(VK_LBUTTON)` and `PostMessage`s state changes — keep it O(1) and allocation-free. Windows cannot reliably distinguish file drags from other drags globally; the approximation is "left button held while moving near the ball". When active: if snapped, slide out; start a ~900ms pulse timer redrawing the layered pixels with a glowing ring (draw ellipse ring with varying alpha; reuse the existing DIB + premultiply path, composing icon + ring). When the drag leaves or button releases → restore the logo-only pixels; if snapped, slide back.
- Keep `WM_DROPFILES` acceptance working in both states (the layered window already receives it).

## Position persistence (Dart seam)

- `UserPreferences` gains nullable `floatingTargetX` / `floatingTargetY` (doubles, JSON-safe, version stays 1 with tolerant parsing like other optional fields).
- Channel `tagtag/windows_floating_drop_target`: on drag end the native side calls `savePosition {x, y}`; Dart handler (`lib/platform/windows_floating_drop_target.dart`) persists via `TagTagController.updatePreferences`. On enable/startup, Dart passes the saved position via a new `setPosition` method; native applies it (clamped to the nearest monitor's work area) instead of the default corner, restoring snapped docking if the point sits at an edge.
- Settings change logging picks the new fields up through the existing `_describePreferenceChanges` only if they pass through `updatePreferences` named args — position writes should NOT spam the log: extend `updatePreferences` with the new fields but skip logging when only position fields changed.

## Acceptance

- Native smoke or unit coverage where feasible; manual verification: drag moves the ball; release snaps to nearest edge with animation; snapped ball hides ~2/3 off-screen; hover expands; dragging a file near the ball (both states) pulses the glow; click still activates Quick Tag; drop still imports; position survives app restart.
- `flutter analyze` 0 issues; full test suite green; Windows Release build succeeds.
