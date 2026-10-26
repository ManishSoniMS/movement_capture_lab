import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'camera_choice.dart';

enum CaptureOrientation { auto, landscape, portrait }

class MovementCaptureConfig {
  MovementCaptureConfig({
    Duration maxDuration = const Duration(seconds: 30),
    this.countdown = const Duration(seconds: 3),
    this.stableBeforeStart = const Duration(milliseconds: 1500),
    this.violationGrace = const Duration(milliseconds: 400),
    this.maxRestarts = 3,
    this.resolution = ResolutionPreset.high,
    this.preferredCameraId,
    this.cameraRotationDegrees = 0,
    this.mirrorExternalPreview,
    this.mirrorFrontPreview,
    this.mirrorBackPreview,
    this.orientation = CaptureOrientation.auto,
    this.allowRecordingWithoutLiveChecks = true,
    this.showSkeleton = true,
    this.skeletonMinLikelihood = 0.5,
    this.safeZoneInset = 0.075,
    this.minLandmarkLikelihood = 0.5,
    this.minMeanLuma = 60,
    this.maxMeanLuma = 200,
    this.maxClippedFraction = 0.25,
    this.minCenterToBorderLuma = 0.6,
    this.analysisInterval = const Duration(milliseconds: 150),
    this.metadata = const {},
    this.restoreOrientations = const [],
  })  : assert(
          const {0, 90, 180, 270}.contains(cameraRotationDegrees),
          'cameraRotationDegrees must be 0, 90, 180 or 270',
        ),
        maxDuration = _clampDuration(maxDuration);

  static const Duration minAllowedDuration = Duration(seconds: 5);
  static const Duration maxAllowedDuration = Duration(seconds: 30);

  /// Screens whose shorter side is at least this (logical pixels) count as
  /// tablets for [CaptureOrientation.auto] and for the wide layout.
  static const double tabletShortestSide = 600;

  final Duration maxDuration;
  final Duration countdown;
  final Duration stableBeforeStart;
  final Duration violationGrace;
  final int maxRestarts;
  final ResolutionPreset resolution;

  /// Camera ID the operator chose last time (from `onCameraChanged`). Used if
  /// still connected; otherwise the default rule applies.
  final String? preferredCameraId;

  /// Rotation of the USB camera image relative to upright, for the quality
  /// checks only. Fixed per installation: the webcam does not rotate with the
  /// tablet. Built-in cameras ignore this.
  final int cameraRotationDegrees;

  /// Display-only preview mirroring per camera type. null = platform default
  /// (see [mirrorPreviewFor]). Recorded files are never changed.
  final bool? mirrorExternalPreview;
  final bool? mirrorFrontPreview;
  final bool? mirrorBackPreview;

  final CaptureOrientation orientation;

  /// When a device cannot send frames during recording: true = record without
  /// checks and report liveChecks=false; false = show the error instead.
  final bool allowRecordingWithoutLiveChecks;

  /// Draw the tracked skeleton on the preview (independent of the debug
  /// overlay).
  final bool showSkeleton;

  /// Points below this likelihood are not drawn.
  final double skeletonMinLikelihood;

  /// Fraction of width/height kept clear at each edge (wide-lens distortion).
  final double safeZoneInset;
  final double minLandmarkLikelihood;
  final int minMeanLuma;
  final int maxMeanLuma;
  final double maxClippedFraction;
  final double minCenterToBorderLuma;
  final Duration analysisInterval;

  /// Passed through untouched to the uploader (e.g. chatSessionId).
  final Map<String, String> metadata;

  /// Orientations to restore when the screen closes. Empty = system default.
  final List<DeviceOrientation> restoreOrientations;

  /// iOS's camera plugin already mirrors the front camera (preview and file),
  /// so mirroring it again would flip it back.
  bool mirrorPreviewFor(CameraKind kind, TargetPlatform platform) =>
      switch (kind) {
        CameraKind.external => mirrorExternalPreview ?? true,
        CameraKind.front =>
          mirrorFrontPreview ?? (platform != TargetPlatform.iOS),
        CameraKind.back => mirrorBackPreview ?? false,
      };

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
