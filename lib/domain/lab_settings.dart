import 'package:movement_capture/movement_capture.dart';

enum UploaderMode { mock, mockFail, inspection, http }

/// In-memory settings for one lab session. Note the chosen values after
/// on-site tuning; they become the kiosk app's defaults.
class LabSettings {
  double maxDurationS = 30;
  double countdownS = 0; // 0 = mode default
  double stableMs = 1500;
  double graceMs = 400;
  double maxRestarts = 3;
  int rotation = 0;
  ResolutionPreset resolution = ResolutionPreset.high;
  double safeZoneInset = 0.075;
  double minLikelihood = 0.5;
  double minLuma = 60;
  double maxLuma = 200;
  double maxClipped = 0.25;
  double minCenterToBorder = 0.6;
  double analysisIntervalMs = 150;
  bool? mirrorExternal; // null = platform default
  bool? mirrorFront;
  bool? mirrorBack;
  CaptureOrientation orientation = CaptureOrientation.auto;
  bool allowNoLiveChecks = true;

  /// Camera the operator last picked (in memory only).
  String? lastCameraId;
  UploaderMode uploaderMode = UploaderMode.mock;
  bool debugOverlay = true;
  bool showSkeleton = true;
  final Set<CaptureStep> steps = {
    CaptureStep.fullBody,
    CaptureStep.face,
    CaptureStep.hands,
    CaptureStep.feet,
  };
  double closeUpDurationS = 10;
  bool feetUseBackCamera = false;
  CaptureMode mode = CaptureMode.assisted;
  bool voiceEnabled = true;
  bool voiceInAssisted = false;
  String voiceLanguage = 'en-IN';

  MovementCaptureConfig toConfig() => MovementCaptureConfig(
        maxDuration: Duration(seconds: maxDurationS.round()),
        steps: [
          for (final s in CaptureStep.values)
            if (steps.contains(s)) s,
        ],
        stepDurations: {
          for (final s in const [
            CaptureStep.face,
            CaptureStep.hands,
            CaptureStep.feet,
          ])
            s: Duration(seconds: closeUpDurationS.round()),
        },
        stepCameras: feetUseBackCamera
            ? const {CaptureStep.feet: CameraKind.back}
            : const {},
        countdown:
            countdownS < 1 ? null : Duration(seconds: countdownS.round()),
        mode: mode,
        voiceInAssisted: voiceInAssisted,
        stableBeforeStart: Duration(milliseconds: stableMs.round()),
        violationGrace: Duration(milliseconds: graceMs.round()),
        maxRestarts: maxRestarts.round(),
        resolution: resolution,
        preferredCameraId: lastCameraId,
        cameraRotationDegrees: rotation,
        mirrorExternalPreview: mirrorExternal,
        mirrorFrontPreview: mirrorFront,
        mirrorBackPreview: mirrorBack,
        orientation: orientation,
        allowRecordingWithoutLiveChecks: allowNoLiveChecks,
        showSkeleton: showSkeleton,
        safeZoneInset: safeZoneInset,
        minLandmarkLikelihood: minLikelihood,
        minMeanLuma: minLuma.round(),
        maxMeanLuma: maxLuma.round(),
        maxClippedFraction: maxClipped,
        minCenterToBorderLuma: minCenterToBorder,
        analysisInterval: Duration(milliseconds: analysisIntervalMs.round()),
        metadata: {
          'chatSessionId': 'lab-${DateTime.now().millisecondsSinceEpoch}'
        },
      );

  /// One line to paste into the PR / tuning notes.
  String summary() =>
      'duration=${maxDurationS.round()}s countdown=${countdownS < 1 ? 'auto' : '${countdownS.round()}s'} '
      'stable=${stableMs.round()}ms grace=${graceMs.round()}ms restarts=${maxRestarts.round()} '
      'rotation=$rotation res=${resolution.name} inset=${safeZoneInset.toStringAsFixed(3)} '
      'likelihood=${minLikelihood.toStringAsFixed(2)} luma=${minLuma.round()}–${maxLuma.round()} '
      'clipped=${maxClipped.toStringAsFixed(2)} centre/border=${minCenterToBorder.toStringAsFixed(2)} '
      'interval=${analysisIntervalMs.round()}ms '
      'mirror(usb/front/back)=${mirrorExternal ?? 'auto'}/${mirrorFront ?? 'auto'}/${mirrorBack ?? 'auto'} '
      'orientation=${orientation.name} noLiveChecks=$allowNoLiveChecks skeleton=$showSkeleton '
      'steps=${steps.map((s) => s.name).join('+')} '
      'closeUp=${closeUpDurationS.round()}s feetBack=$feetUseBackCamera '
      'mode=${mode.name} voice=$voiceEnabled/$voiceLanguage';
}
