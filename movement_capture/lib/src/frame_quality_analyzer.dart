import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'capture_issue.dart';
import 'config.dart';
import 'luma_stats.dart';

class UnsupportedFrameFormat implements Exception {
  const UnsupportedFrameFormat(this.detail);
  final String detail;
  @override
  String toString() => 'UnsupportedFrameFormat: $detail';
}

/// One required body point, in normalised upright image coordinates (0–1).
/// x/y are -1 when ML Kit did not return the point.
class LandmarkPoint {
  const LandmarkPoint({
    required this.name,
    required this.x,
    required this.y,
    required this.likelihood,
    required this.ok,
  });
  final String name;
  final double x;
  final double y;
  final double likelihood;
  final bool ok;
}

class FrameMetrics {
  const FrameMetrics({
    required this.luma,
    required this.faces,
    required this.poses,
    required this.landmarks,
    required this.issues,
    required this.analysesPerSecond,
  });
  final LumaStats luma;
  final int faces;
  final int poses;
  final List<LandmarkPoint> landmarks;
  final Set<CaptureIssue> issues;
  final int analysesPerSecond;
}

class FrameCheck {
  const FrameCheck({required this.issues, required this.at, required this.metrics});
  final Set<CaptureIssue> issues;
  final DateTime at;
  final FrameMetrics metrics;

  CaptureIssue? get topIssue {
    for (final issue in CaptureIssue.values) {
      if (issues.contains(issue)) return issue;
    }
    return null;
  }
}

/// Yes/no quality gate. Never used for movement analysis.
class FrameQualityAnalyzer {
  FrameQualityAnalyzer(this._config)
      : _pose = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base,
          ),
        ),
        _faces = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.fast,
            minFaceSize: 0.05, // faces are small at full-body distance
          ),
        );

  final MovementCaptureConfig _config;
  final PoseDetector _pose;
  final FaceDetector _faces;

  static const List<PoseLandmarkType> _required = [
    PoseLandmarkType.nose,
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
  ];

  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _runTimes = [];

  /// Returns null when the frame is skipped (busy or throttled).
  ///
  /// Everything before the first `await` runs synchronously inside the camera
  /// callback. The camera reuses the frame buffer once the callback returns,
  /// so brightness is computed and the bytes are copied first.
  Future<FrameCheck?> analyze(CameraImage image) async {
    final now = DateTime.now();
    if (_busy || now.difference(_lastRun) < _config.analysisInterval) {
      return null;
    }
    _busy = true;
    _lastRun = now;
    _runTimes
      ..add(now)
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 1));

    try {
      final input = _toInputImage(image); // validates format, copies bytes
      final plane = image.planes.first;
      final luma = LumaStats.fromLumaPlane(
        plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
      );

      final (poses, faces) =
          await (_pose.processImage(input), _faces.processImage(input)).wait;

      final issues = <CaptureIssue>{};
      final lightIssue = luma.issueFor(_config);
      if (lightIssue != null) issues.add(lightIssue);
      if (faces.length > 1) issues.add(CaptureIssue.multiplePeople);

      var points = const <LandmarkPoint>[];
      if (poses.isEmpty) {
        issues.add(CaptureIssue.noPerson);
      } else {
        points = _evaluate(poses.first, _uprightSize(image));
        if (points.any((p) => !p.ok)) issues.add(CaptureIssue.outOfFrame);
      }

      return FrameCheck(
        issues: issues,
        at: now,
        metrics: FrameMetrics(
          luma: luma,
          faces: faces.length,
          poses: poses.length,
          landmarks: points,
          issues: issues,
          analysesPerSecond: _runTimes.length,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async {
    await _pose.close();
    await _faces.close();
  }

  InputImage _toInputImage(CameraImage image) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format != InputImageFormat.nv21 || image.planes.length != 1) {
      throw UnsupportedFrameFormat(
        'expected single-plane NV21, got ${image.format.raw} '
        'with ${image.planes.length} planes',
      );
    }
    final rotation =
        InputImageRotationValue.fromRawValue(_config.cameraRotationDegrees) ??
            InputImageRotation.rotation0deg;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: Uint8List.fromList(plane.bytes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// ML Kit returns coordinates in the upright (rotated) image.
  Size _uprightSize(CameraImage image) {
    final swap = _config.cameraRotationDegrees == 90 ||
        _config.cameraRotationDegrees == 270;
    return swap
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
  }

  List<LandmarkPoint> _evaluate(Pose pose, Size upright) {
    final inset = _config.safeZoneInset;
    return [
      for (final type in _required)
        _point(pose.landmarks[type], type, upright, inset),
    ];
  }

  LandmarkPoint _point(
    PoseLandmark? lm,
    PoseLandmarkType type,
    Size upright,
    double inset,
  ) {
    if (lm == null) {
      return LandmarkPoint(
          name: type.name, x: -1, y: -1, likelihood: 0, ok: false);
    }
    final nx = lm.x / upright.width;
    final ny = lm.y / upright.height;
    final inside =
        nx >= inset && nx <= 1 - inset && ny >= inset && ny <= 1 - inset;
    return LandmarkPoint(
      name: type.name,
      x: nx,
      y: ny,
      likelihood: lm.likelihood,
      ok: inside && lm.likelihood >= _config.minLandmarkLikelihood,
    );
  }
}
