import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../domain/capture_issue.dart';
import '../domain/config.dart';
import '../domain/frame_analyzer.dart';
import '../domain/frame_metrics.dart';
import '../domain/luma_stats.dart';
import '../domain/pose_topology.dart';

/// ML Kit pose + face detection plus luma stats.
class MlKitFrameAnalyzer implements FrameAnalyzer {
  MlKitFrameAnalyzer(this._config, {required int Function() rotationDegrees})
      : _rotationDegrees = rotationDegrees,
        _pose = PoseDetector(
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
  final int Function() _rotationDegrees;
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
  @override
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
      final rotation = _normalise(_rotationDegrees());
      final input = _toInputImage(image, rotation); // validates, copies bytes
      final luma = _luma(image);

      final (poses, faces) =
          await (_pose.processImage(input), _faces.processImage(input)).wait;

      final issues = <CaptureIssue>{};
      final lightIssue = luma.issueFor(_config);
      if (lightIssue != null) issues.add(lightIssue);
      if (faces.length > 1) issues.add(CaptureIssue.multiplePeople);

      final upright = _uprightSize(image, rotation);
      var points = const <LandmarkPoint>[];
      var allPose = const <PosePoint>[];
      if (poses.isEmpty) {
        issues.add(CaptureIssue.noPerson);
      } else {
        points = _evaluate(poses.first, upright);
        allPose = _allPoints(poses.first, upright);
        if (points.any((p) => !p.ok)) issues.add(CaptureIssue.outOfFrame);
      }
      final faceBoxes = [
        for (final f in faces) _normalisedRect(f.boundingBox, upright),
      ];

      return FrameCheck(
        issues: issues,
        at: now,
        overlay: OverlayFrame(pose: allPose, faces: faceBoxes),
        metrics: FrameMetrics(
          luma: luma,
          faces: faces.length,
          poses: poses.length,
          landmarks: points,
          issues: issues,
          analysesPerSecond: _runTimes.length,
          rotationDegrees: rotation,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> close() async {
    await _pose.close();
    await _faces.close();
  }

  static int _normalise(int degrees) {
    final d = ((degrees % 360) + 360) % 360;
    // Snap to the nearest quarter turn; ML Kit accepts only these.
    return ((d + 45) ~/ 90 % 4) * 90;
  }

  InputImage _toInputImage(CameraImage image, int rotationDegrees) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final supported = image.planes.length == 1 &&
        (format == InputImageFormat.nv21 ||
            format == InputImageFormat.bgra8888);
    if (!supported) {
      throw UnsupportedFrameFormat(
        'expected single-plane NV21 (Android) or BGRA8888 (iOS), got '
        '${image.format.raw} with ${image.planes.length} planes',
      );
    }
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
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

  LumaStats _luma(CameraImage image) {
    final plane = image.planes.first;
    final isBgra = InputImageFormatValue.fromRawValue(image.format.raw) ==
        InputImageFormat.bgra8888;
    return isBgra
        ? LumaStats.fromBgra(plane.bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: plane.bytesPerRow)
        : LumaStats.fromLumaPlane(plane.bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: plane.bytesPerRow);
  }

  /// ML Kit returns coordinates in the upright (rotated) image.
  Size _uprightSize(CameraImage image, int rotationDegrees) {
    final swap = rotationDegrees == 90 || rotationDegrees == 270;
    return swap
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
  }

  List<PosePoint> _allPoints(Pose pose, Size upright) => [
        for (final lm in pose.landmarks.values)
          PosePoint(
            type: PoseJoint.values.byName(lm.type.name),
            x: lm.x / upright.width,
            y: lm.y / upright.height,
            likelihood: lm.likelihood,
          ),
      ];

  Rect _normalisedRect(Rect r, Size upright) => Rect.fromLTRB(
        r.left / upright.width,
        r.top / upright.height,
        r.right / upright.width,
        r.bottom / upright.height,
      );

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
