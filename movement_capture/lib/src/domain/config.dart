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
    this.showSkeleton = true,
    this.skeletonMinLikelihood = 0.2,
    this.safeZoneInset = 0.075,
    this.minLandmarkLikelihood = 0.5,
    this.faceMinWidthFraction = 0.28,
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

  /// Draw the tracked skeleton on the preview (independent of the debug
  /// overlay).
  final bool showSkeleton;

  /// Points below this likelihood are not drawn; up to 0.7 they are drawn
  /// faded. The quality checks still use [minLandmarkLikelihood].
  final double skeletonMinLikelihood;

  /// Fraction of width/height kept clear at each edge (wide-lens distortion).
  final double safeZoneInset;
  final double minLandmarkLikelihood;

  /// Face step: face box width must be at least this share of frame width.
  final double faceMinWidthFraction;
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
