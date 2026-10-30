import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../domain/quality_status.dart';
import 'customization.dart';

/// Two plain lines above the camera picture (never on it): is the subject in
/// frame, and is the video good enough. Each has an icon, a sentence and a
/// colour, so colour is never the only signal.
class QualityStatusBar extends StatelessWidget {
  const QualityStatusBar({
    super.key,
    required this.status,
    required this.strings,
    required this.icons,
    required this.goodColor,
    required this.warningColor,
    required this.badColor,
  });

  final ValueListenable<QualityStatus?> status;
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;
  final Color goodColor;
  final Color warningColor;
  final Color badColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.inverseSurface,
      child: ValueListenableBuilder<QualityStatus?>(
        valueListenable: status,
        builder: (context, value, _) {
          final problem = value?.problem;
          final lines = value == null
              ? const <Widget>[]
              : [
                  _StatusLine(
                    key: const ValueKey('status-in-frame'),
                    icon: value.inFrame ? icons.statusGood : icons.statusBad,
                    text: value.inFrame
                        ? strings.statusInFrame
                        : strings.statusNotInFrame,
                    color: value.inFrame ? goodColor : badColor,
                  ),
                  _StatusLine(
                    key: const ValueKey('status-quality'),
                    icon: problem == null
                        ? icons.statusGood
                        : icons.statusWarning,
                    text: strings.qualityLine(problem),
                    color: problem == null ? goodColor : warningColor,
                  ),
                ];
          return ConstrainedBox(
            // Reserve the height so the picture does not jump when the first
            // result arrives.
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 32,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: lines,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(width: 12),
        // Simple fade when the sentence changes; nothing else animates.
        Flexible(
            child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            text,
            key: ValueKey(text),
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: theme.colorScheme.onInverseSurface),
          ),
        )),
      ],
    );
  }
}
