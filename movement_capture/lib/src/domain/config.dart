import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'camera_choice.dart';
import 'capture_step.dart';

enum CaptureOrientation { auto, landscape, portrait }

/// B2B: a helper is present. B2C: the user is on their own.
enum CaptureMode { assisted, selfGuided }

class MovementCaptureConfig {
  MovementCaptureConfig({
    Duration maxDuration = const Duration(seconds: 30),
    this.steps = const [
      CaptureStep.fullBody,
      CaptureStep.face,
      CaptureStep.hands,
      CaptureStep.feet,
    ],
    this.stepDurations = const {},
    this.skippableSteps = const {
      CaptureStep.face,
      CaptureStep.hands,
      CaptureStep.feet,
    },
    this.stepCameras = const {},
    this.countdown,
    this.stableBeforeStart = const Duration(milliseconds: 1500),
    this.violationGrace = const Duration(milliseconds: 400),
    this.maxRestarts = 3,
    this.resolution = ResolutionPreset.high,
    this.preferredCameraId,
    this.cameraRotationDegrees,
    this.mirrorExternalPreview,
    this.mirrorFrontPreview,
    this.mirrorBackPreview,
    this.orientation = CaptureOrientation.auto,
    this.mode = CaptureMode.assisted,
    this.voiceInAssisted = false,
    this.voiceIssueRepeat = const Duration(seconds: 6),
    this.allowRecordingWithoutLiveChecks = true,
    this.reviewBeforeUpload = true,
    this.blockOnPoorQuality = false,
    this.showDetails = true,
    this.allowUseAnyway = true,
    this.qualityHold = const Duration(milliseconds: 500),
    this.qualitySampleInterval = const Duration(milliseconds: 300),
    this.minCameraShortSide = 480,
    this.minCameraFps = 15,
    this.minSharpness = 40,
    this.maxMotion = 10,
    this.faceMaxWidthFraction = 0.7,
    this.bodyMinHeightFraction = 0.55,
    this.bodyMaxHeightFraction = 0.92,
    this.minInFrameShare = 0.9,
    this.minCheckPassShare = 0.8,
    this.minRecordedDuration = const Duration(seconds: 3),
    this.safeZoneInset = 0.075,
    this.minLandmarkLikelihood = 0.5,
    this.faceMinWidthFraction = 0.28,
    this.handTracking = true,
    this.requireBothHands = true,
    this.offerSideChoice = true,
    this.minMeanLuma = 60,
    this.maxMeanLuma = 200,
    this.maxClippedFraction = 0.25,
    this.minCenterToBorderLuma = 0.6,
    this.analysisInterval,
    this.metadata = const {},
    this.restoreOrientations = const [],
  })  : assert(
          cameraRotationDegrees == null ||
              const {0, 90, 180, 270}.contains(cameraRotationDegrees),
          'cameraRotationDegrees must be null, 0, 90, 180 or 270',
        ),
        maxDuration = _clampDuration(maxDuration);

  static const Duration minAllowedDuration = Duration(seconds: 5);
  static const Duration maxAllowedDuration = Duration(seconds: 30);

  /// Screens whose shorter side is at least this (logical pixels) count as
  /// tablets for [CaptureOrientation.auto] and for the wide layout.
  static const double tabletShortestSide = 600;

  /// Duration of the fullBody step (the "system input"), clamped to 5–30 s.
  final Duration maxDuration;

  /// Steps in recording order.
  final List<CaptureStep> steps;

  /// Durations for the other steps (default 10 s each), clamped to 5–30 s.
  final Map<CaptureStep, Duration> stepDurations;

  /// Steps that may be skipped.
  final Set<CaptureStep> skippableSteps;

  /// Optional camera type to switch to when a step begins. Falls back to the
  /// current camera when none of that kind exists.
  final Map<CaptureStep, CameraKind> stepCameras;

  /// null = 3 s (assisted) or 5 s (self-guided: time to step back).
  final Duration? countdown;

  Duration get effectiveCountdown =>
      countdown ??
      (mode == CaptureMode.selfGuided
          ? const Duration(seconds: 5)
          : const Duration(seconds: 3));

  final Duration stableBeforeStart;
  final Duration violationGrace;
  final int maxRestarts;
  final ResolutionPreset resolution;

  /// Camera ID the operator chose last time (from `onCameraChanged`). Used if
  /// still connected; otherwise the default rule applies.
  final String? preferredCameraId;

  /// Rotation applied to analysed frames so the skeleton lines up with the
  /// preview. null = automatic (recommended): iOS 0; Android front
  /// (sensor + screen); Android back/USB (sensor − screen). Set a value only
  /// for an unusual USB camera that the automatic rule gets wrong.
  final int? cameraRotationDegrees;

  /// Display-only preview mirroring per camera type. null = platform default
  /// (see [mirrorPreviewFor]). Recorded files are never changed.
  final bool? mirrorExternalPreview;
  final bool? mirrorFrontPreview;
  final bool? mirrorBackPreview;

  final CaptureOrientation orientation;

  final CaptureMode mode;

  /// Speak prompts in assisted mode too (self-guided always speaks if a voice
  /// is supplied).
  final bool voiceInAssisted;

  /// How often an unresolved problem is repeated aloud.
  final Duration voiceIssueRepeat;

  bool get speaks => mode == CaptureMode.selfGuided || voiceInAssisted;

  /// When a device cannot send frames during recording: true = record without
  /// checks and report liveChecks=false; false = show the error instead.
  final bool allowRecordingWithoutLiveChecks;

  /// Show each recorded clip for approval (Use / Record again) before upload.
  final bool reviewBeforeUpload;

  /// true = poor quality (not in frame, too dark, ...) stops the countdown and
  /// aborts a recording, as the strict flow did. false (default) = the status
  /// area shows the problem and the patient or operator decides.
  final bool blockOnPoorQuality;

  /// Shows the technical details on the camera screen: step counter and
  /// live readouts. Hiding only hides: the quality checks keep running and
  /// their results are still saved. Default on (UNCONFIRMED: the team may
  /// prefer off for patients).
  final bool showDetails;

  /// After a recording that failed the overall check, offer "Use anyway".
  final bool allowUseAnyway;

  // Quality-check thresholds. UNCONFIRMED: no model requirement was found in
  // the repo; the ML team must set these. Brightness uses [minMeanLuma] and
  // [maxMeanLuma], face distance uses [faceMinWidthFraction].

  /// A verdict must hold this long before the on-screen status changes.
  final Duration qualityHold;

  /// Time between sharpness and movement samples (~3 per second).
  final Duration qualitySampleInterval;

  /// Camera check, done once when a camera opens. UNCONFIRMED defaults: the
  /// ML team must set them. Shortest side of the stream in pixels, and
  /// measured frames per second. Below either = weak camera.
  final int minCameraShortSide;
  final double minCameraFps;

  /// Minimum variance of the Laplacian on the 160 px brightness copy
  /// (squared brightness levels). Below = "blurry".
  final double minSharpness;

  /// Maximum mean brightness change between consecutive samples (0–255).
  /// Above = "hold still".
  final double maxMotion;

  /// Face step: face box wider than this share of the frame = "too close".
  final double faceMaxWidthFraction;

  /// Full-body step: head-to-ankle span as a share of the frame height,
  /// below = "move closer", above = "move back".
  final double bodyMinHeightFraction;
  final double bodyMaxHeightFraction;

  /// Overall check after recording: least share of time in frame.
  final double minInFrameShare;

  /// Overall check after recording: least share of time each quality check
  /// must have passed.
  final double minCheckPassShare;

  /// Overall check after recording: shortest acceptable clip.
  final Duration minRecordedDuration;

  /// Fraction of width/height kept clear at each edge (wide-lens distortion).
  final double safeZoneInset;
  final double minLandmarkLikelihood;

  /// Face step: face box width must be at least this share of frame width.
  final double faceMinWidthFraction;

  /// Hands step: track hands with MediaPipe (21 points per hand).
  final bool handTracking;

  /// Hands step: both hands must be visible.
  final bool requireBothHands;

  /// Hands and feet steps: ask whether to scan both sides, left only or
  /// right only. Both is the default. Turn off to always scan both.
  final bool offerSideChoice;
  final int minMeanLuma;
  final int maxMeanLuma;
  final double maxClippedFraction;
  final double minCenterToBorderLuma;

  /// Minimum time between analysed frames. null = 66 ms (~15/s), or 150 ms on
  /// low-memory devices. Each analysis also waits for the previous one.
  final Duration? analysisInterval;

  Duration effectiveAnalysisInterval({required bool lowMemoryDevice}) =>
      analysisInterval ??
      (lowMemoryDevice
          ? const Duration(milliseconds: 150)
          : const Duration(milliseconds: 66));

  /// Passed through untouched to the uploader (e.g. chatSessionId).
  final Map<String, String> metadata;

  /// Orientations to restore when the screen closes. Empty = system default.
  final List<DeviceOrientation> restoreOrientations;

  /// [steps] without duplicates, never empty.
  List<CaptureStep> get effectiveSteps {
    final seen = <CaptureStep>{};
    final result = [
      for (final s in steps)
        if (seen.add(s)) s,
    ];
    return result.isEmpty ? const [CaptureStep.fullBody] : result;
  }

  /// How long [step] records: [maxDuration] for the full body, 10 s for the
  /// others unless [stepDurations] says otherwise. Always clamped.
  Duration durationFor(CaptureStep step) {
    if (step == CaptureStep.fullBody && !stepDurations.containsKey(step)) {
      return maxDuration;
    }
    return _clampDuration(stepDurations[step] ?? step.defaultDuration);
  }

  /// Extra, display-only mirroring of the preview (and the skeleton with it).
  /// Front cameras are already mirrored by the system on both platforms, so
  /// the default is off for them. USB cameras default to a mirror view.
  bool mirrorPreviewFor(CameraKind kind, TargetPlatform platform) =>
      switch (kind) {
        CameraKind.external => mirrorExternalPreview ?? true,
        CameraKind.front => mirrorFrontPreview ?? false,
        CameraKind.back => mirrorBackPreview ?? false,
      };

  /// Whether the skeleton must be flipped relative to the preview. On Android
  /// the system mirrors the front-camera preview but not the analysed frames;
  /// on iOS both are mirrored together.
  bool overlayFlipFor(CameraKind kind, TargetPlatform platform) =>
      platform == TargetPlatform.android && kind == CameraKind.front;

  /// Review playback should look like the live preview did. The live preview
  /// was mirrored if the system mirrored it (front cameras) XOR the extra
  /// display flip was on. The file itself is mirrored only on the iOS front
  /// camera.
  bool reviewMirrorFor(CameraKind kind, TargetPlatform platform) {
    final shownMirrored =
        mirrorPreviewFor(kind, platform) != (kind == CameraKind.front);
    final fileMirrored =
        platform == TargetPlatform.iOS && kind == CameraKind.front;
    return shownMirrored != fileMirrored;
  }

  List<DeviceOrientation> orientationsFor(double shortestSide) {
    const landscape = [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    const portrait = [DeviceOrientation.portraitUp];
    return switch (orientation) {
      CaptureOrientation.landscape => landscape,
      CaptureOrientation.portrait => portrait,
      CaptureOrientation.auto =>
        shortestSide >= tabletShortestSide ? landscape : portrait,
    };
  }

  static Duration _clampDuration(Duration d) {
    if (d < minAllowedDuration) return minAllowedDuration;
    if (d > maxAllowedDuration) return maxAllowedDuration;
    return d;
  }
}
