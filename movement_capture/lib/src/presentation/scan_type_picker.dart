import 'package:flutter/material.dart';

import '../domain/capture_step.dart';
import 'customization.dart';

/// Four large tiles, one per scan type, and a Start button that stays off
/// until a tile is chosen. The host owns the selection (see ScanSelection).
/// The chosen tile has a border, a check mark and a colour, so colour is not
/// the only signal.
class ScanTypePicker extends StatelessWidget {
  const ScanTypePicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onStart,
    required this.strings,
    required this.icons,
  });

  final CaptureStep? selected;
  final ValueChanged<CaptureStep> onSelected;
  final VoidCallback onStart;
  final MovementCaptureStrings strings;
  final MovementCaptureIcons icons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(CaptureStep step) => _Tile(
          key: ValueKey('scan-tile-${step.name}'),
          icon: icons.step(step),
          label: strings.stepTitle(step),
          selectedLabel: strings.scanTypeSelected,
          selected: selected == step,
          onTap: () => onSelected(step),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(strings.scanTypeTitle,
              style: theme.textTheme.headlineMedium),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Two rows that share the height, so all four tiles always fit
            // on screen without scrolling.
            child: Column(
              children: [
                for (final row in const [
                  [CaptureStep.fullBody, CaptureStep.face],
                  [CaptureStep.hands, CaptureStep.feet],
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          for (final step in row) ...[
                            if (step == row.last) const SizedBox(width: 16),
                            Expanded(child: tile(step)),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const ValueKey('scan-start'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 72)),
            onPressed: selected == null ? null : onStart,
            child: Text(strings.scanTypeStart,
                style: theme.textTheme.headlineSmall),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.label,
    required this.selectedLabel,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String selectedLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      value: selected ? selectedLabel : null,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: Material(
        color:
            selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 4 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 72),
                    const SizedBox(height: 12),
                    Text(label, style: theme.textTheme.headlineSmall),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 12,
                  right: 12,
                  child:
                      Icon(Icons.check_circle, size: 36, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
