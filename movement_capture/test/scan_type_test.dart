import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

void main() {
  group('ScanSelection', () {
    test('nothing is pre-selected and Start is off', () {
      final s = ScanSelection();
      expect(s.selected, isNull);
      expect(s.canStart, isFalse);
    });

    test('selecting a type deselects the previous one', () {
      final s = ScanSelection()..select(CaptureStep.face);
      s.select(CaptureStep.feet);
      expect(s.selected, CaptureStep.feet);
      expect(CaptureStep.values.where(s.isSelected), [CaptureStep.feet]);
      expect(s.canStart, isTrue);
    });

    test('hands and feet need the side step; face and full body do not', () {
      for (final step in CaptureStep.values) {
        final s = ScanSelection()..select(step);
        expect(s.needsSideChoice,
            step == CaptureStep.hands || step == CaptureStep.feet,
            reason: '$step');
      }
    });

    test('the scan request carries exactly one scan type', () {
      final s = ScanSelection()..select(CaptureStep.hands);
      expect(s.steps, [CaptureStep.hands]);
      expect(ScanSelection().steps, isEmpty);
      final config = MovementCaptureConfig(steps: s.steps);
      expect(config.effectiveSteps, [CaptureStep.hands]);
    });
  });

  group('ScanTypePicker', () {
    Future<void> pump(WidgetTester t, ScanSelection sel,
        {VoidCallback? onStart}) async {
      await t.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      late StateSetter set;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            set = setState;
            return ScanTypePicker(
              selected: sel.selected,
              onSelected: (s) => set(() => sel.select(s)),
              onStart: onStart ?? () {},
              strings: const MovementCaptureStrings(),
              icons: const MovementCaptureIcons(),
            );
          }),
        ),
      ));
    }

    FilledButton start(WidgetTester t) =>
        t.widget<FilledButton>(find.byKey(const ValueKey('scan-start')));

    testWidgets('four labelled tiles, none selected, Start disabled',
        (t) async {
      await pump(t, ScanSelection());
      for (final label in ['Full body', 'Face', 'Hands', 'Feet']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(start(t).onPressed, isNull);
    });

    testWidgets('tap marks one tile with a check; next tap moves it',
        (t) async {
      final sel = ScanSelection();
      await pump(t, sel);
      await t.tap(find.byKey(const ValueKey('scan-tile-face')));
      await t.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(start(t).onPressed, isNotNull);
      await t.tap(find.byKey(const ValueKey('scan-tile-feet')));
      await t.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(sel.selected, CaptureStep.feet);
    });

    testWidgets('tiles and Start are large touch targets', (t) async {
      await pump(t, ScanSelection()..select(CaptureStep.face));
      for (final s in CaptureStep.values) {
        final size = t.getSize(find.byKey(ValueKey('scan-tile-${s.name}')));
        expect(size.shortestSide, greaterThanOrEqualTo(56));
      }
      expect(t.getSize(find.byKey(const ValueKey('scan-start'))).height,
          greaterThanOrEqualTo(56));
    });
  });

  group('show camera details', () {
    test('config default is on and can be turned off', () {
      expect(MovementCaptureConfig().showDetails, isTrue);
      expect(MovementCaptureConfig(showDetails: false).showDetails, isFalse);
    });

    test('hiding details never touches the quality checks', () {
      // Camera cannot run under flutter test: guard the source instead. Only
      // the screen may read the switch; checks and results live elsewhere.
      for (final f in [
        'lib/src/presentation/controller.dart',
        'lib/src/data/mlkit_frame_analyzer.dart',
        'lib/src/domain/quality_summary.dart',
        'lib/src/domain/quality_status.dart',
      ]) {
        expect(File(f).readAsStringSync(), isNot(contains('showDetails')),
            reason: f);
      }
    });
  });
}
