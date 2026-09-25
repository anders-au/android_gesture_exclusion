import 'package:android_gesture_exclusion/android_gesture_exclusion.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Plain `test` rather than `testWidgets`: these cases await a real
  // platform-message round trip, and `testWidgets` runs in a FakeAsync zone
  // where only microtasks that the frame pump drives will ever complete.
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.github.b4tchkn/android_gesture_exclusion');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('sends the given rects to the platform channel', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      receivedCall = call;
      return null;
    });

    await AndroidGestureExclusion.instance.setRects(const [Rect.fromLTRB(0, 1, 10, 20)]);

    expect(receivedCall?.method, 'setSystemGestureExclusionRects');
    expect(receivedCall?.arguments, [
      {'left': 0, 'top': 1, 'right': 10, 'bottom': 20},
    ]);
  });

  test('clears the rects with an empty payload', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      receivedCall = call;
      return null;
    });

    await AndroidGestureExclusion.instance.clear();

    expect(receivedCall?.method, 'setSystemGestureExclusionRects');
    expect(receivedCall?.arguments, isEmpty);
  });

  test('never throws when the native implementation is missing', () async {
    // No mock handler is installed, so the channel reports a missing plugin —
    // the state a retained engine is in while no Activity is attached.
    await expectLater(AndroidGestureExclusion.instance.setRects(const [Rect.fromLTRB(0, 0, 1, 1)]), completes);
  });

  test('drops rects that cannot be encoded', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      receivedCall = call;
      return null;
    });

    await AndroidGestureExclusion.instance.setRects(const [Rect.fromLTWH(0, 0, double.nan, 10), Rect.fromLTWH(0, 0, double.infinity, 10)]);

    expect(receivedCall, isNull);
  });

  group('gestureExclusionRects', () {
    // A 400x800 dp window on a 2.0 dpr device, i.e. 800x1600 physical pixels,
    // with a 24dp status bar and a 48dp navigation gesture bar.
    const devicePixelRatio = 2.0;
    const windowSize = Size(400, 800);
    const systemInsets = EdgeInsets.only(top: 24, bottom: 48);

    test('keeps the margins in physical pixels', () {
      final rects = gestureExclusionRects(
        globalPosition: const Offset(10, 20),
        size: const Size(100, 50),
        devicePixelRatio: devicePixelRatio,
        windowSize: windowSize,
        systemInsets: systemInsets,
        horizontalMargin: 4,
        verticalMargin: 6,
      );

      expect(rects, const [Rect.fromLTRB(16, 34, 224, 146)]);
    });

    test('clamps the widget rect to the window', () {
      final rects = gestureExclusionRects(
        globalPosition: const Offset(-20, -40),
        size: const Size(100, 50),
        devicePixelRatio: devicePixelRatio,
        windowSize: windowSize,
        systemInsets: systemInsets,
      );

      expect(rects, const [Rect.fromLTRB(0, 0, 160, 20)]);
    });

    test('clears the exclusion when the widget has no area of its own', () {
      final rects = gestureExclusionRects(
        globalPosition: const Offset(0, -100),
        size: const Size(100, 50),
        devicePixelRatio: devicePixelRatio,
        windowSize: windowSize,
        systemInsets: systemInsets,
        coverDeviceEdges: true,
      );

      expect(rects, isEmpty);
    });

    test('adds a strip on each device edge the widget does not reach', () {
      final rects = gestureExclusionRects(
        globalPosition: const Offset(10, 200),
        size: const Size(100, 50),
        devicePixelRatio: devicePixelRatio,
        windowSize: windowSize,
        systemInsets: systemInsets,
        coverDeviceEdges: true,
      );

      expect(rects, const [
        // The widget itself.
        Rect.fromLTRB(20, 400, 220, 500),
        // The status bar strip, spanning the widget's width.
        Rect.fromLTRB(20, 0, 220, 48),
        // The navigation gesture bar strip, spanning the widget's width.
        Rect.fromLTRB(20, 1504, 220, 1600),
      ]);
    });

    test('does not repeat an edge the widget already reaches', () {
      final rects = gestureExclusionRects(
        globalPosition: Offset.zero,
        size: windowSize,
        devicePixelRatio: devicePixelRatio,
        windowSize: windowSize,
        systemInsets: systemInsets,
        coverDeviceEdges: true,
      );

      expect(rects, const [Rect.fromLTRB(0, 0, 800, 1600)]);
    });

    test('adds no strip when the system reserves no inset for that edge', () {
      final rects = gestureExclusionRects(
        globalPosition: const Offset(10, 200),
        size: const Size(100, 50),
        devicePixelRatio: devicePixelRatio,
        windowSize: windowSize,
        systemInsets: EdgeInsets.zero,
        coverDeviceEdges: true,
      );

      expect(rects, const [Rect.fromLTRB(20, 400, 220, 500)]);
    });
  });
}
