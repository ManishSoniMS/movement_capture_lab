import 'capture_step.dart';

/// Single-choice scan type. Nothing is selected at first, so the patient
/// makes an active choice; selecting one type replaces the previous one.
class ScanSelection {
  CaptureStep? _selected;

  CaptureStep? get selected => _selected;

  bool isSelected(CaptureStep step) => _selected == step;

  void select(CaptureStep step) => _selected = step;

  bool get canStart => _selected != null;

  /// Hands and feet continue to the both / left / right step.
  bool get needsSideChoice => _selected?.hasSides ?? false;

  /// The steps for the session: exactly the chosen type, or none.
  List<CaptureStep> get steps => _selected == null ? const [] : [_selected!];
}
