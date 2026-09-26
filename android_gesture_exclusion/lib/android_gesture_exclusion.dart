import 'dart:io';
import 'dart:math' as math;

import 'package:android_gesture_exclusion_platform_interface/android_gesture_exclusion_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Provides public API to call setSystemGestureExclusionRects manually.
/// Manually set the Rect of the Widget obtained through GlobalKey.
class AndroidGestureExclusion {
  AndroidGestureExclusion._();

  /// The instance of [AndroidGestureExclusionPlatform] to use.
  /// By default, the implementation of
  /// [MethodChannelAndroidGestureExclusionPlatformInterface] is used.
  static final instance = AndroidGestureExclusion._();

  static AndroidGestureExclusionPlatform get _platform => AndroidGestureExclusionPlatform.instance;

  /// Set the rects you want to exclude.
  ///
  /// Never fails. The rects are a best-effort hint, and there is nothing to
  /// exclude while no Activity is attached to the engine — for example a cached
  /// engine that outlives its Activity, or an engine started headless from a
  /// service.
  Future<void> setRects(List<Rect> rects) async {
    // With no attached Flutter view there is no Activity to exclude rects from,
    // so the call is skipped instead of relying on the platform side to ignore
    // it.
    if (PlatformDispatcher.instance.views.isEmpty) return;

    final usableRects = <Rect>[];
    for (final rect in rects) {
      // NaN and infinite bounds cannot be encoded for the platform channel, so
      // they are dropped rather than failing (or clearing) the whole update.
      if (rect.hasNaN || rect.isInfinite) continue;
      usableRects.add(rect);
    }
    if (rects.isNotEmpty && usableRects.isEmpty) return;

    await _send(usableRects);
  }

  /// Clear exclusion rects.
  Future<void> clear() => setRects(const <Rect>[]);

  /// Sends [rects] to the platform, swallowing failures.
  ///
  /// Callers are layout and visibility callbacks that cannot handle an error,
  /// so a failure must never surface as an unhandled async error.
  Future<void> _send(List<Rect> rects) async {
    try {
      await _platform.setSystemGestureExclusionRects(rects);
    } on MissingPluginException {
      // No native implementation for this engine.
    } on PlatformException {
      // The native side rejected the update; nothing actionable for callers.
    }
  }
}

/// Widget to Exclude the area of wrapped Widget.
/// Exclude wrapped Widget each time performLayout of RenderObject is called.
class AndroidGestureExclusionContainer extends StatefulWidget {
  /// Constructs an instance of [AndroidGestureExclusionContainer].
  ///
  /// The [verticalExclusionMargin] is optional.
  /// Default value is 0.
  ///
  /// The [horizontalExclusionMargin] is optional.
  /// Default value is 0.
  ///
  /// The [coverDeviceEdges] is optional.
  /// Default value is false.
  ///
  /// The [child] is always required.
  const AndroidGestureExclusionContainer({
    Key? key,
    this.verticalExclusionMargin = 0,
    this.horizontalExclusionMargin = 0,
    this.coverDeviceEdges = false,
    required this.child,
  }) : super(key: key);

  /// Margin value to be set vertically to the [child]
  final double verticalExclusionMargin;

  /// Margin value to be set horizontally to the [child]
  final double horizontalExclusionMargin;

  /// Whether the excluded area also reaches the top and bottom of the device.
  ///
  /// The system gesture areas hug the physical edges of the screen, so a gesture
  /// that starts on the status bar, or on the bottom navigation gesture bar, is
  /// claimed by the system before the [child] ever sees it - even while the
  /// bounds of the [child] are excluded. When this is true, a strip as tall as
  /// the corresponding system inset is excluded at the top and at the bottom of
  /// the window, across the horizontal extent of the [child].
  ///
  /// One rect is used per edge on purpose: the framework only takes a limited
  /// vertical extent of the exclusions into account, so a single window-tall
  /// rect could only ever be honoured at one end of the screen.
  ///
  /// Note that covering an edge also means system gestures that start on it
  /// (for example swipe up for Home) are not recognised over that strip while
  /// this container is on screen.
  final bool coverDeviceEdges;

  /// Widget to exclude gesture.
  final Widget child;

  @override
  State<AndroidGestureExclusionContainer> createState() => _AndroidGestureExclusionContainerState();
}

class _AndroidGestureExclusionContainerState extends State<AndroidGestureExclusionContainer> {
  final _visibilityKey = UniqueKey();
  final _exclusionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return widget.child;

    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 0) {
          AndroidGestureExclusion.instance.clear();
        } else {
          final currentContext = _exclusionKey.currentContext;
          final renderBox = currentContext?.findRenderObject() as RenderBox?;
          if (renderBox == null) {
            // The child is gone (or was never laid out), so there is no area to
            // exclude and no meaningful rect to compute.
            AndroidGestureExclusion.instance.clear();
            return;
          }
          final mediaQuery = MediaQuery.of(context);
          final rects = gestureExclusionRects(
            globalPosition: renderBox.localToGlobal(Offset.zero),
            size: renderBox.size,
            devicePixelRatio: mediaQuery.devicePixelRatio,
            windowSize: mediaQuery.size,
            systemInsets: mediaQuery.viewPadding,
            horizontalMargin: widget.horizontalExclusionMargin,
            verticalMargin: widget.verticalExclusionMargin,
            coverDeviceEdges: widget.coverDeviceEdges,
          );
          AndroidGestureExclusion.instance.setRects(rects);
        }
      },
      child: _GestureExclusion(
        key: _exclusionKey,
        verticalExclusionMargin: widget.verticalExclusionMargin,
        horizontalExclusionMargin: widget.horizontalExclusionMargin,
        coverDeviceEdges: widget.coverDeviceEdges,
        child: widget.child,
      ),
    );
  }
}

class _GestureExclusion extends SingleChildRenderObjectWidget {
  const _GestureExclusion({
    super.key,
    required this.verticalExclusionMargin,
    required this.horizontalExclusionMargin,
    required this.coverDeviceEdges,
    required Widget super.child,
  });

  final double verticalExclusionMargin;
  final double horizontalExclusionMargin;
  final bool coverDeviceEdges;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return _RenderGestureExclusion(
      verticalExclusionMargin: verticalExclusionMargin,
      horizontalExclusionMargin: horizontalExclusionMargin,
      coverDeviceEdges: coverDeviceEdges,
      devicePixelRatio: mediaQuery.devicePixelRatio,
      windowSize: mediaQuery.size,
      systemInsets: mediaQuery.viewPadding,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGestureExclusion renderObject,
  ) {
    final mediaQuery = MediaQuery.of(context);
    renderObject
      ..devicePixelRatio = mediaQuery.devicePixelRatio
      ..windowSize = mediaQuery.size
      ..systemInsets = mediaQuery.viewPadding
      ..verticalExclusionMargin = verticalExclusionMargin
      ..horizontalExclusionMargin = horizontalExclusionMargin
      ..coverDeviceEdges = coverDeviceEdges;
  }

  @override
  void didUnmountRenderObject(covariant RenderObject renderObject) {
    AndroidGestureExclusion.instance.clear();
  }
}

class _RenderGestureExclusion extends RenderProxyBox {
  _RenderGestureExclusion({
    required this.verticalExclusionMargin,
    required this.horizontalExclusionMargin,
    required this.coverDeviceEdges,
    required this.devicePixelRatio,
    required this.windowSize,
    required this.systemInsets,
  });

  double verticalExclusionMargin;
  double horizontalExclusionMargin;
  bool coverDeviceEdges;
  double devicePixelRatio;
  Size windowSize;
  EdgeInsets systemInsets;

  @override
  void performLayout() {
    super.performLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The rects are only known once layout has run, and the render object can
      // already be detached by the time the callback fires (a route popped in
      // the same frame), in which case its old area must not be re-excluded.
      if (!attached) return;
      final rects = gestureExclusionRects(
        globalPosition: localToGlobal(Offset.zero),
        size: size,
        devicePixelRatio: devicePixelRatio,
        windowSize: windowSize,
        systemInsets: systemInsets,
        horizontalMargin: horizontalExclusionMargin,
        verticalMargin: verticalExclusionMargin,
        coverDeviceEdges: coverDeviceEdges,
      );
      AndroidGestureExclusion.instance.setRects(rects);
    });
  }
}

Rect _rectWithMargin(
  Offset globalPosition,
  Size size,
  double devicePixelRatio,
  double horizontalMargin,
  double verticalMargin,
) {
  final left = globalPosition.dx * devicePixelRatio;
  final top = globalPosition.dy * devicePixelRatio;
  final right = left + size.width * devicePixelRatio;
  final bottom = top + size.height * devicePixelRatio;
  return Rect.fromLTRB(
    left - horizontalMargin,
    top - verticalMargin,
    right + horizontalMargin,
    bottom + verticalMargin,
  );
}

/// Builds the exclusion rects for a widget laid out at [globalPosition] with
/// [size], in the physical pixel space of the view the platform side excludes
/// from. [windowSize] is the logical size of that view (as reported by
/// `MediaQuery`), scaled by [devicePixelRatio] here.
///
/// The widget's own rect is clamped to the window, and rects that have no area
/// (the widget is scrolled out of view) are dropped, which clears the previous
/// exclusion instead of excluding nothing.
///
/// When [coverDeviceEdges] is set, one extra rect is added per device edge the
/// widget does not already reach - the top and the bottom of the window - each
/// as tall as the corresponding [systemInsets] edge and as wide as the widget
/// (including [horizontalMargin]). Those are the areas the system reserves for
/// its own gestures, where a touch that starts on the very edge of the screen
/// never reaches the widget.
@visibleForTesting
List<Rect> gestureExclusionRects({
  required Offset globalPosition,
  required Size size,
  required double devicePixelRatio,
  required Size windowSize,
  required EdgeInsets systemInsets,
  double horizontalMargin = 0,
  double verticalMargin = 0,
  bool coverDeviceEdges = false,
}) {
  final windowWidth = windowSize.width * devicePixelRatio;
  final windowHeight = windowSize.height * devicePixelRatio;
  final widgetRect = _rectWithMargin(
    globalPosition,
    size,
    devicePixelRatio,
    horizontalMargin,
    verticalMargin,
  );
  final clampedRect = Rect.fromLTRB(
    math.max(0, widgetRect.left),
    math.max(0, widgetRect.top),
    math.min(windowWidth, widgetRect.right),
    math.min(windowHeight, widgetRect.bottom),
  );

  final rects = <Rect>[
    if (!clampedRect.isEmpty) clampedRect,
  ];
  // With no area of its own there is nothing to protect, so no edge strips are
  // added for a widget that is scrolled out of the window.
  if (!coverDeviceEdges || rects.isEmpty) return rects;

  final topStrip = systemInsets.top * devicePixelRatio;
  if (clampedRect.top > 0 && topStrip > 0) {
    rects.add(Rect.fromLTRB(clampedRect.left, 0, clampedRect.right, topStrip));
  }

  final bottomStrip = systemInsets.bottom * devicePixelRatio;
  if (clampedRect.bottom < windowHeight && bottomStrip > 0) {
    rects.add(
      Rect.fromLTRB(
        clampedRect.left,
        windowHeight - bottomStrip,
        clampedRect.right,
        windowHeight,
      ),
    );
  }

  return rects;
}
