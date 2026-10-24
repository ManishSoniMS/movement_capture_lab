import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class MovementCaptureConfig {
  MovementCaptureConfig({
    Duration maxDuration = const Duration(seconds: 30),
    this.countdown = const Duration(seconds: 3),
    this.stableBeforeStart = const Duration(milliseconds: 1500),
    this.violationGrace = const Duration(milliseconds: 400),
    this.maxRestarts = 3,
    this.resolution = ResolutionPreset.high,
    this.cameraRotationDegrees = 0,
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

  final Duration maxDuration;
  final Duration countdown;
  final Duration stableBeforeStart;
  final Duration violationGrace;
  final int maxRestarts;
  final ResolutionPreset resolution;

  /// Rotation of the webcam image relative to upright, for ML Kit only.
  /// Fixed per installation: the webcam does not rotate with the tablet.
  final int cameraRotationDegrees;

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

  static Duration _clampDuration(Duration d) {
    if (d < minAllowedDuration) return minAllowedDuration;
    if (d > maxAllowedDuration) return maxAllowedDuration;
    return d;
  }
}
