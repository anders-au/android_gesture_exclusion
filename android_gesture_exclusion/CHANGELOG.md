## 0.4.2

- Add `AndroidGestureExclusionContainer.coverDeviceEdges` (default `false`).
  When enabled, the exclusion also covers the top and the bottom of the device,
  across the width of the child: the system gesture areas hug the physical edges
  of the screen, so a touch that starts on the status bar or on the navigation
  gesture bar is claimed by the system before the child sees it. A strip as tall
  as the corresponding system inset is used per edge, because the framework only
  takes a limited vertical extent of the exclusions into account.
- Clamp the computed rect to the window and clear the exclusion (rather than
  sending a zero-area rect) when the child has no area of its own.

## 0.4.1

- Keep the native method-call handler installed for the lifetime of the
  engine, so calls made while no `Activity` is attached (a cached/retained
  engine that outlives its Activity, or a headless engine started from a
  service) are acknowledged as no-ops instead of throwing
  `MissingPluginException`.
- Tolerate malformed rect payloads instead of throwing while decoding them, and
  report unknown methods with `notImplemented()` instead of leaving the caller
  without a reply.
- `AndroidGestureExclusion.setRects`/`clear` now return `Future<void>` and never
  throw; rects that cannot be encoded (`NaN`/infinite bounds) are dropped, and
  calls are skipped while the engine has no attached Flutter view.
- `AndroidGestureExclusionContainer` no longer computes a rect for a child that
  is gone, and no longer re-excludes its old area after unmount.

## 0.4.0

- Update dependency gradle to v8.9
- Update dependency com.android.tools.build:gradle to v8.5.1

## 0.3.0

- Update android_gesture_exclusion_platform_interface to 0.2.0

## 0.2.1

- Fix gesture_detector version to ^0.4.0+2

## 0.2.0

- Updates minimum supported SDK version to Flutter 3.3.0+/Dart 3.0.0+
- Update dependency com.android.tools.build:gradle to v8.5.0
- Update kotlin monorepo to v2
- Update dependency gradle to v8.8

## 0.1.0

- Initial release.
