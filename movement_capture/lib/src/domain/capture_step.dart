/// The parts of a capture session, recorded in the order of
/// MovementCaptureConfig.steps.
enum CaptureStep {
  fullBody,
  face,
  hands,
  feet;

  /// Runs the body-pose detector.
  bool get usesPose => this == CaptureStep.fullBody;

  /// Runs a face detector (count only for fullBody; detailed for face).
  bool get usesFace => this == CaptureStep.fullBody || this == CaptureStep.face;

  /// Runs MediaPipe hand tracking (if enabled).
  bool get usesHands => this == CaptureStep.hands;

  /// Steps where the person may scan one side only.
  bool get hasSides => this == CaptureStep.hands || this == CaptureStep.feet;

  /// Produces landmarks.json.
  bool get recordsLandmarks => usesFace || usesHands;

  Duration get defaultDuration => this == CaptureStep.fullBody
      ? const Duration(seconds: 30)
      : const Duration(seconds: 10);
}
