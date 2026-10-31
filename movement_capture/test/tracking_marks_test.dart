import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/hand_topology.dart';
import 'package:movement_capture/src/domain/overlay_builder.dart';
import 'package:movement_capture/src/domain/pose_topology.dart';
import 'package:movement_capture/src/presentation/quality_status_bar.dart';
import 'package:movement_capture/src/presentation/skeleton_layer.dart';

const _colors =
    SkeletonColors(body: Colors.blue, hand: Colors.green, foot: Colors.orange);

PosePoint _p(PoseJoint j, double x, double y) =>
    PosePoint(type: j, x: x, y: y, likelihood: 1);

Widget _layer(OverlayFrame? frame, {required bool drawMarks}) => MaterialApp(
      home: SizedBox(
        width: 400,
        height: 400,
        child: SkeletonLayer(
          frames: ValueNotifier(frame),
          colors: _colors,
          minLikelihood: 0.2,
          transition: Duration.zero,
          drawMarks: drawMarks,
        ),
      ),
    );

RenderObject _painter(WidgetTester t) => t.renderObject(find
    .descendant(
        of: find.byType(SkeletonLayer), matching: find.byType(CustomPaint))
    .first);

void main() {
  group('skeleton layer', () {
    final body = OverlayFrame(pose: [
      _p(PoseJoint.leftShoulder, 0.3, 0.3),
      _p(PoseJoint.rightShoulder, 0.7, 0.3),
      _p(PoseJoint.leftAnkle, 0.4, 0.9),
    ]);

    testWidgets('draws body marks', (t) async {
      await t.pumpWidget(_layer(body, drawMarks: true));
      expect(_painter(t), paints..circle());
    });

    testWidgets('showSkeleton false draws nothing', (t) async {
      await t.pumpWidget(_layer(body, drawMarks: false));
      expect(_painter(t), isNot(paints..circle()));
      expect(_painter(t), isNot(paints..line()));
    });

    testWidgets('a frame with only face data draws nothing', (t) async {
      final faceOnly = buildOverlay(
        pose: [
          _p(PoseJoint.nose, 0.5, 0.2),
          _p(PoseJoint.leftEye, 0.45, 0.18),
          _p(PoseJoint.rightEye, 0.55, 0.18),
          _p(PoseJoint.leftMouth, 0.47, 0.25),
          _p(PoseJoint.rightMouth, 0.53, 0.25),
        ],
        hands: const [],
        choice: SideChoice.both,
        framesMirrored: false,
      );
      await t.pumpWidget(_layer(faceOnly, drawMarks: true));
      expect(_painter(t), isNot(paints..circle()));
      expect(_painter(t), isNot(paints..line()));
      expect(_painter(t), isNot(paints..rrect()));
      expect(_painter(t), isNot(paints..path()));
    });

    testWidgets('hand points are drawn', (t) async {
      final hand = HandSnapshot(
        handedness: 'Left',
        score: 1,
        points: [for (var i = 0; i < 21; i++) Offset(0.3 + i / 100, 0.5)],
        depth: List.filled(21, 0),
      );
      await t.pumpWidget(_layer(OverlayFrame(hands: [hand]), drawMarks: true));
      expect(_painter(t), paints..circle());
    });
  });

  test('showDetails hides only the counter and debug panel, not the marks', () {
    // Source guard (the screen needs a camera): the marks layer is gated on
    // showSkeleton only; showDetails gates the step counter and the debug
    // panel.
    final screen = File('lib/src/presentation/screen.dart').readAsStringSync();
    final gate = RegExp(r'if \((.*?)\)\s*Transform\.flip').firstMatch(screen)!;
    expect(gate.group(1), contains('showSkeleton'));
    expect(gate.group(1), isNot(contains('showDetails')));
    expect(screen,
        contains('widget.showDebugOverlay && _controller.config.showDetails'));
  });

  test('the marks do not rebuild the camera preview', () {
    // The layer repaints through its own AnimationController and notifier;
    // the screen never listens to `overlay`.
    final screen = File('lib/src/presentation/screen.dart').readAsStringSync();
    expect(screen, isNot(contains('overlay.addListener')));
    final layer =
        File('lib/src/presentation/skeleton_layer.dart').readAsStringSync();
    expect(layer, contains('RepaintBoundary'));
    expect(layer, contains('repaint: repaint'));
  });

  group('out-of-frame line in the status area', () {
    Future<ValueNotifier<Duration?>> pump(WidgetTester t,
        {Duration? left, bool unavailable = false}) async {
      final warning = ValueNotifier<Duration?>(left);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: QualityStatusBar(
            status: ValueNotifier(null),
            cameraWeak: ValueNotifier(false),
            strings: const MovementCaptureStrings(),
            icons: const MovementCaptureIcons(),
            goodColor: Colors.green,
            warningColor: Colors.amber,
            badColor: Colors.red,
            outOfFrameWarning: warning,
            stopUnavailable: unavailable,
          ),
        ),
      ));
      return warning;
    }

    testWidgets('no warning, no line', (t) async {
      await pump(t);
      expect(find.byKey(const ValueKey('status-out-of-frame')), findsNothing);
    });

    testWidgets('warning shows the countdown and updates', (t) async {
      final w = await pump(t, left: const Duration(milliseconds: 1600));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Please come back into the frame — stopping in 2'),
          findsOneWidget);
      w.value = const Duration(milliseconds: 900);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Please come back into the frame — stopping in 1'),
          findsOneWidget);
      w.value = null;
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('status-out-of-frame')), findsNothing);
    });

    testWidgets('feet notice renders', (t) async {
      await pump(t, unavailable: true);
      expect(find.text('Auto-stop is not available for this scan'),
          findsOneWidget);
    });
  });
}
