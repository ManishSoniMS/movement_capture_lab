import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/capture_state.dart';
import 'package:movement_capture/src/domain/quality_status.dart';
import 'package:movement_capture/src/domain/quality_summary.dart';
import 'package:movement_capture/src/presentation/controller.dart';
import 'package:movement_capture/src/presentation/quality_status_bar.dart';
import 'package:movement_capture/src/presentation/review_view.dart';

class _NoUpload implements MovementUploader {
  @override
  Future<String> upload(MovementClip clip,
          {required void Function(double progress) onProgress,
          required UploadCancellation cancellation}) async =>
      'id';
}

const _strings = MovementCaptureStrings();
const _icons = MovementCaptureIcons();

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: child),
    );

void main() {
  group('status area', () {
    Future<void> pump(WidgetTester t, QualityStatus? s) async {
      await t.pumpWidget(_host(QualityStatusBar(
        status: ValueNotifier(s),
        strings: _strings,
        icons: _icons,
        goodColor: Colors.green,
        warningColor: Colors.amber,
        badColor: Colors.red,
      )));
    }

    testWidgets('good: both lines say so, with check icons', (t) async {
      await pump(t, const QualityStatus(inFrame: true, problem: null));
      expect(find.text('You are in the frame'), findsOneWidget);
      expect(find.text('Video quality: Good'), findsOneWidget);
      expect(find.byIcon(_icons.statusGood), findsNWidgets(2));
    });

    testWidgets('not in frame is red with its own icon', (t) async {
      await pump(t, const QualityStatus(inFrame: false, problem: null));
      expect(find.text('You are not in the frame'), findsOneWidget);
      expect(find.byIcon(_icons.statusBad), findsOneWidget);
    });

    testWidgets('each quality problem shows its sentence and a warning icon',
        (t) async {
      final expected = {
        QualityProblem.tooDark: 'Video quality: Too dark',
        QualityProblem.tooBright: 'Video quality: Too bright',
        QualityProblem.tooFar: 'Video quality: Move closer',
        QualityProblem.tooClose: 'Video quality: Move back',
        QualityProblem.blurry:
            'Video quality: Blurry. Check the camera or hold still',
        QualityProblem.moving: 'Video quality: Please hold still',
      };
      for (final e in expected.entries) {
        await pump(t, QualityStatus(inFrame: true, problem: e.key));
        await t.pumpAndSettle();
        expect(find.text(e.value), findsOneWidget, reason: '${e.key}');
        expect(find.byIcon(_icons.statusWarning), findsOneWidget);
      }
    });

    testWidgets('nothing is shown before the first result', (t) async {
      await pump(t, null);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('text is large enough to read at arm\'s length', (t) async {
      await pump(t, const QualityStatus(inFrame: true, problem: null));
      final text = t.widget<Text>(find.text('You are in the frame'));
      final size = Theme.of(t.element(find.byType(QualityStatusBar)))
          .textTheme
          .headlineSmall!
          .fontSize!;
      expect(text.style!.fontSize ?? size, greaterThanOrEqualTo(24));
    });
  });

  group('after-recording result', () {
    QualitySummary summary({required bool pass}) => QualitySummary.from(
          [
            for (var t = 0; t < 10000; t += 300)
              QualitySample(
                  tMs: t, inFrame: pass || t < 3000, problems: const {})
          ],
          durationMs: 10000,
          config: MovementCaptureConfig(),
        );

    Future<void> pump(WidgetTester t, QualitySummary q,
        {bool allowUseAnyway = true}) async {
      final controller = MovementCaptureController(
        config: MovementCaptureConfig(
            steps: [CaptureStep.face], allowUseAnyway: allowUseAnyway),
        uploader: _NoUpload(),
      );
      addTearDown(controller.dispose);
      await t.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_host(ReviewView(
        controller: controller,
        review: Reviewing(
          video: File('does-not-exist.mp4'),
          quality: q,
          cameraKind: CameraKind.front,
          fileMirrored: false,
        ),
        strings: _strings,
        icons: _icons,
        activeColor: Colors.green,
        onCancel: () {},
      )));
      await t.pump();
    }

    testWidgets('good recording: "Good for analysis" and Continue', (t) async {
      await pump(t, summary(pass: true));
      expect(find.text('Good for analysis.'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Use anyway'), findsNothing);
      expect(find.text('Record again'), findsOneWidget);
    });

    testWidgets('failed recording: reason, Record again and Use anyway',
        (t) async {
      await pump(t, summary(pass: false));
      expect(
          find.textContaining(
              'Please record again. You were out of the frame for part of the video.'),
          findsOneWidget);
      expect(find.text('Record again'), findsOneWidget);
      expect(find.text('Use anyway'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('Use anyway is hidden when the config switch is off',
        (t) async {
      await pump(t, summary(pass: false), allowUseAnyway: false);
      expect(find.text('Use anyway'), findsNothing);
      expect(find.text('Record again'), findsOneWidget);
    });

    testWidgets('nothing measured: no verdict is claimed', (t) async {
      await pump(
          t,
          QualitySummary.from(const [],
              durationMs: 10000, config: MovementCaptureConfig()));
      expect(find.text('Good for analysis.'), findsNothing);
      expect(find.textContaining('Please record again'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
    });
  });

  test('no tracking marks are drawn on the camera picture', () {
    // Camera and ML Kit cannot run under flutter test, so guard the source:
    // the only painter left is the fixed safe-zone box (it never moves).
    final painters = [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        for (final m in RegExp(r'class (\w+) extends CustomPainter')
            .allMatches(f.readAsStringSync()))
          m.group(1)!,
    ];
    expect(painters, ['_SafeZonePainter']);
    for (final name in const [
      'skeleton_layer.dart',
      'tracker_overlay.dart',
      'tracker_guide.dart',
    ]) {
      expect(File('lib/src/presentation/$name').existsSync(), isFalse);
    }
  });
}
