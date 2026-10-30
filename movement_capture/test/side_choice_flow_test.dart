import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/presentation/controller.dart';
import 'package:movement_capture/src/presentation/side_choice_view.dart';
import 'package:movement_capture/src/presentation/speech_planner.dart';
import 'package:movement_capture/src/domain/capture_state.dart';

class _NoUpload implements MovementUploader {
  @override
  Future<String> upload(MovementClip clip,
          {required void Function(double progress) onProgress,
          required UploadCancellation cancellation}) async =>
      'id';
}

MovementCaptureController _controller(
        {List<CaptureStep> steps = const [CaptureStep.hands],
        bool offer = true}) =>
    MovementCaptureController(
      config: MovementCaptureConfig(steps: steps, offerSideChoice: offer),
      uploader: _NoUpload(),
    );

void main() {
  const strings = MovementCaptureStrings();

  group('controller: the choice', () {
    test('asks first and defaults to both', () {
      final c = _controller();
      expect(c.awaitingSideChoice, isTrue);
      expect(c.sideChoiceFor(CaptureStep.hands), SideChoice.both);
      c.dispose();
    });

    test('choosing left only is recorded and the question goes away', () {
      final c = _controller()..chooseSides(SideChoice.leftOnly);
      expect(c.awaitingSideChoice, isFalse);
      expect(c.results.single.sideChoice, SideChoice.leftOnly);
      expect(c.results.single.statusOf(BodySide.right),
          SideStatus.notScannedByChoice);
      c.dispose();
    });

    test('Start is ignored until the question is answered', () {
      final c = _controller();
      c.startRequested(); // state is Initializing; must not throw or arm
      expect(c.awaitingSideChoice, isTrue);
      c.dispose();
    });

    test('steps without sides are never asked; the host can turn it off', () {
      final face = _controller(steps: [CaptureStep.face]);
      expect(face.awaitingSideChoice, isFalse);
      face.dispose();
      final off = _controller(offer: false);
      expect(off.awaitingSideChoice, isFalse);
      expect(off.sideChoiceFor(CaptureStep.hands), SideChoice.both);
      off.dispose();
    });
  });

  group('choice screen', () {
    Future<List<SideChoice>> pump(WidgetTester tester, CaptureStep step) async {
      final picked = <SideChoice>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SideChoiceView(
            step: step,
            strings: strings,
            onChoose: picked.add,
            onCancel: () {},
          ),
        ),
      ));
      return picked;
    }

    testWidgets('three tiles, Both first and selected', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, CaptureStep.hands);
      expect(find.text('Which hands would you like to scan?'), findsOneWidget);
      final labels = ['Both hands', 'Left hand only', 'Right hand only'];
      final xs = [
        for (final l in labels) tester.getTopLeft(find.text(l)).dx,
      ];
      expect(xs, [...xs]..sort(), reason: 'Both is first');
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // The marker sits in the Both tile only.
      final marker = tester.getCenter(find.byIcon(Icons.check_circle));
      expect((marker - tester.getCenter(find.text('Both hands'))).distance,
          lessThan(
              (marker - tester.getCenter(find.text('Left hand only'))).distance));
    });

    testWidgets('tiles are at least 56 dp and tapping answers', (tester) async {
      final picked = await pump(tester, CaptureStep.feet);
      expect(find.text('Which feet would you like to scan?'), findsOneWidget);
      expect(tester.getSize(find.byType(InkWell).first).height,
          greaterThanOrEqualTo(56));
      await tester.tap(find.text('Right foot only'));
      expect(picked, [SideChoice.rightOnly]);
    });
  });

  group('results summary', () {
    Future<void> show(WidgetTester tester, List<CaptureStepResult> steps) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SideSummary(steps: steps, strings: strings)),
        ));

    testWidgets('left only: scanned and not scanned (your choice)',
        (tester) async {
      await show(tester, const [
        CaptureStepResult(
            step: CaptureStep.hands,
            analysisId: 'a',
            sideChoice: SideChoice.leftOnly),
      ]);
      expect(find.text('Left hand — ✓ scanned'), findsOneWidget);
      expect(find.text('Right hand — not scanned (your choice)'),
          findsOneWidget);
    });

    testWidgets('right only and both', (tester) async {
      await show(tester, const [
        CaptureStepResult(
            step: CaptureStep.hands,
            analysisId: 'a',
            sideChoice: SideChoice.rightOnly),
        CaptureStepResult(step: CaptureStep.feet, analysisId: 'b'),
      ]);
      expect(find.text('Left hand — not scanned (your choice)'),
          findsOneWidget);
      expect(find.text('Right hand — ✓ scanned'), findsOneWidget);
      expect(find.text('Left foot — ✓ scanned'), findsOneWidget);
      expect(find.text('Right foot — ✓ scanned'), findsOneWidget);
    });

    testWidgets('a failed side reads differently from a choice',
        (tester) async {
      await show(tester, const [
        CaptureStepResult(
            step: CaptureStep.hands, sideChoice: SideChoice.leftOnly),
      ]);
      expect(find.text('Left hand — not scanned'), findsOneWidget);
      expect(find.text('Right hand — not scanned (your choice)'),
          findsOneWidget);
    });

    testWidgets('skipped steps and steps without sides are not listed',
        (tester) async {
      await show(tester, const [
        CaptureStepResult(step: CaptureStep.hands, skipped: true),
        CaptureStepResult(step: CaptureStep.face, analysisId: 'f'),
      ]);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('voice', () {
    test('the planner asks the question, then reads the one-sided instruction',
        () {
      final p = SpeechPlanner(strings: strings, mode: CaptureMode.assisted);
      final t = DateTime(2026);
      String? say({required bool awaiting, SideChoice c = SideChoice.both}) =>
          p.next(
              SpeechSnapshot(
                  state: const Checking(),
                  step: CaptureStep.hands,
                  stepIndex: 0,
                  awaitingSideChoice: awaiting,
                  sideChoice: c),
              t);
      expect(say(awaiting: true), 'Which hands would you like to scan?');
      expect(say(awaiting: false, c: SideChoice.leftOnly),
          strings.stepInstructionLeftHand);
    });
  });
}
