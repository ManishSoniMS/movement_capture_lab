import 'package:flutter/material.dart';

import '../domain/body_sides.dart';
import '../domain/capture_step.dart';
import '../domain/result.dart';
import 'customization.dart';

/// "Which hands would you like to scan?" with three large tiles. Both is
/// first and marked as the default; tapping any tile answers and continues.
class SideChoiceView extends StatelessWidget {
  const SideChoiceView({
    super.key,
    required this.step,
    required this.strings,
    required this.onChoose,
    required this.onCancel,
  });

  final CaptureStep step;
  final MovementCaptureStrings strings;
  final ValueChanged<SideChoice> onChoose;
  final VoidCallback onCancel;

  /// Tile height; well above the 56 dp touch minimum.
  static const double tileHeight = 184;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.sideChoiceTitle(step),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final c in SideChoice.values)
                        _Tile(
                          step: step,
                          choice: c,
                          label: strings.sideChoiceLabel(step, c),
                          selected: c == SideChoice.both,
                          onTap: () => onChoose(c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(160, 56)),
                    onPressed: onCancel,
                    child: Text(strings.cancel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.step,
    required this.choice,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CaptureStep step;
  final SideChoice choice;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = step == CaptureStep.feet
        ? Icons.directions_walk
        : Icons.back_hand_outlined;
    Widget glyph(bool flip) => Transform.flip(
          flipX: flip,
          child: Icon(icon, size: 64, color: scheme.onSurface),
        );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: SizedBox(
        width: 260,
        height: SideChoiceView.tileHeight,
        child: Material(
          color:
              selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 4 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: switch (choice) {
                      SideChoice.both => [glyph(false), glyph(true)],
                      SideChoice.leftOnly => [glyph(false)],
                      SideChoice.rightOnly => [glyph(true)],
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selected) ...[
                        Icon(Icons.check_circle, color: scheme.primary),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-side status for each hands / feet step that was not skipped:
/// "Left hand — ✓ scanned", "Right hand — not scanned (your choice)".
/// A failed side reads differently from a side left out by choice.
class SideSummary extends StatelessWidget {
  const SideSummary({super.key, required this.steps, required this.strings});

  final List<CaptureStepResult> steps;
  final MovementCaptureStrings strings;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    final lines = <String>[
      for (final r in steps)
        if (r.step.hasSides && !r.skipped)
          for (final side in BodySide.values)
            strings.sideStatusLine(r.step, side, r.statusOf(side)),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final l in lines) Text(l, style: style)],
    );
  }
}
