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
    required this.cameraWeak,
    required this.strings,
    required this.icons,
    required this.goodColor,
    required this.warningColor,
    required this.badColor,
    this.outOfFrameWarning,
    this.stopUnavailable = false,
  });

  final ValueListenable<QualityStatus?> status;

  /// Camera resolution or frame rate is below the minimum (checked once).
  final ValueListenable<bool> cameraWeak;
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;
  final Color goodColor;
  final Color warningColor;
  final Color badColor;

  /// Time left before "Stop recording if out of frame" stops the recording,
  /// or null (no warning). Shown as a large line, never on the picture.
  final ValueListenable<Duration?>? outOfFrameWarning;

  /// The switch is on but this step cannot use it (feet): small notice.
  final bool stopUnavailable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.inverseSurface,
      child: ValueListenableBuilder<bool>(
        valueListenable: cameraWeak,
        builder: (context, weak, _) => ValueListenableBuilder<QualityStatus?>(
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
            final warning = outOfFrameWarning;
            final extra = <Widget>[
              if (warning != null)
                ValueListenableBuilder<Duration?>(
                  valueListenable: warning,
                  builder: (context, left, _) {
                    if (left == null) return const SizedBox.shrink();
                    final n = (left.inMilliseconds / 1000).ceil();
                    return _StatusLine(
                      key: const ValueKey('status-out-of-frame'),
                      icon: icons.comeBack,
                      text: strings.outOfFrameWarning(n < 1 ? 1 : n),
                      color: badColor,
                      large: true,
                    );
                  },
                ),
              if (stopUnavailable)
                _StatusLine(
                  key: const ValueKey('status-stop-unavailable'),
                  icon: icons.statusWarning,
                  text: strings.outOfFrameStopUnavailable,
                  color: warningColor,
                  small: true,
                ),
            ];
            return ConstrainedBox(
              // Reserve the height so the picture does not jump when the first
              // result arrives.
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(
                  spacing: 32,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...lines,
                    ...extra,
                    if (weak)
                      _StatusLine(
                        key: const ValueKey('status-camera-weak'),
                        icon: icons.statusWarning,
                        text: strings.statusCameraWeak,
                        color: warningColor,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
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
    this.large = false,
    this.small = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool large;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: small ? 24 : (large ? 40 : 32), color: color),
        const SizedBox(width: 12),
        // Simple fade when the sentence changes; nothing else animates.
        Flexible(
            child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            text,
            key: ValueKey(text),
            style: (small
                    ? theme.textTheme.titleMedium
                    : large
                        ? theme.textTheme.headlineMedium
                        : theme.textTheme.headlineSmall)
                ?.copyWith(color: theme.colorScheme.onInverseSurface),
          ),
        )),
      ],
    );
  }
}
