import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../domain/body_sides.dart';
import '../domain/capture_issue.dart';
import '../domain/capture_step.dart';
import '../domain/config.dart';
import '../domain/face_snapshot.dart';
import '../domain/frame_analyzer.dart';
import '../domain/frame_downscaler.dart';
import '../domain/hand_topology.dart';
import '../domain/frame_metrics.dart';
import '../domain/luma_stats.dart';
import '../domain/luma_thumb.dart';
import '../domain/quality_status.dart';
import '../domain/overlay_builder.dart';
import '../domain/pose_topology.dart';
import 'native_bridge.dart';

/// ML t detection plus luma stats, with the detectors chosen per step:
/// full body = pose + fast face count; face = face with landmarks and
/// contours; hands = MediaPipe Hand Landmarker through the plugin (lighting
/// only when it is off or has failed); feet = lighting only (no model tracks
/// feet without the upper body).
class MlKitFrameAnalyzer implements FrameAnalyzer {
  MlKitFrameAnalyzer(
    this._config, {
    required this.step,
    required int Function() rotationDegrees,
    required Duration interval,
    SideChoice Function()? sideChoice,
    bool Function()? framesMirrored,
  })  : _rotationDegrees = rotationDegrees,
        _sideChoice = sideChoice ?? (() => SideChoice.both),
        _framesMirrored = framesMirrored ?? (() => false),
        _interval = interval,
        _handsActive = step.usesHands && _config.handTracking,
        _pose = step.usesPose
            ? PoseDetector(
                options: PoseDetectorOptions(
                  mode: PoseDetectionMode.stream,
                  model: PoseDetectionModel.base,
                ),
              )
            : null,
        _faces = switch (step) {
          CaptureStep.fullBody => FaceDetector(
              options: FaceDetectorOptions(
                performanceMode: FaceDetectorMode.fast,
                minFaceSize: 0.05, // faces are small at full-body distance
              ),
            ),
          CaptureStep.face => FaceDetector(
              options: FaceDetectorOptions(
                performanceMode: FaceDetectorMode.fast,
                enableLandmarks: true,
                enableContours: true,
                minFaceSize: 0.15,
              ),
            ),
          _ => null,
        };

  @override
  final CaptureStep step;
  final MovementCaptureConfig _config;
  final int Function() _rotationDegrees;
  final SideChoice Function() _sideChoice;
  final bool Function() _framesMirrored;
  final Duration _interval;

  /// Hands step: false once MediaPipe failed 3 times in a row.
  bool _handsActive;
  int _handFailures = 0;

  /// Full-body step: the face detector runs on every 3rd analysis; the last
  /// result is reused in between.
  int _faceTick = 0;
  List<Face> _lastFaces = const [];
  final PoseDetector? _pose;
  final FaceDetector? _faces;

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

  /// Sharpness and movement are measured on a small brightness copy every
  /// `qualitySampleInterval` and reused in between. Only the previous thumb is
  /// kept (for the movement difference); it is never stored or logged.
  LumaThumb? _prevThumb;
  DateTime _lastQualitySample = DateTime.fromMillisecondsSinceEpoch(0);
  double _sharpness = double.infinity;
  double _motion = 0;

  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _runTimes = [];

  /// Everything before the first `await` runs synchronously inside the camera
  /// callback. The camera reuses the frame buffer once the callback returns,
  /// so brightness is computed and the bytes are copied first.
  @override
  Future<FrameCheck?> analyze(CameraImage image) async {
    final now = DateTime.now();
    if (_busy || now.difference(_lastRun) < _interval) {
      return null;
    }
    _busy = true;
    _lastRun = now;
    _runTimes
      ..add(now)
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 1));

    try {
      final rotation = _normalise(_rotationDegrees());
      // Validates the format for every step and copies the bytes.
      final input = _toInputImage(image, rotation);
      final luma = _luma(image);
      _sampleQuality(image, now);
      final upright = _uprightSize(image, rotation);
      // Like the ML Kit copy above, the hand image must be made before the
      // first await: the camera reuses the buffer after the callback returns.
      final handFrame = _handsActive ? _handImage(image, rotation) : null;

      final poseFuture =
          _pose?.processImage(input) ?? Future.value(const <Pose>[]);
      final runFace = _faces != null &&
          (step != CaptureStep.fullBody || _faceTick++ % 3 == 0);
      final faceFuture = runFace
          ? _faces.processImage(input)
          : Future.value(
              step == CaptureStep.fullBody ? _lastFaces : const <Face>[]);
      final handsFuture = handFrame == null
          ? Future.value(const <HandSnapshot>[])
          : _detectHands(handFrame);
      final (poses, faces, hands) =
          await (poseFuture, faceFuture, handsFuture).wait;
      if (runFace && step == CaptureStep.fullBody) _lastFaces = faces;

      final issues = <CaptureIssue>{};
      final lightIssue = luma.issueFor(_config);
      if (lightIssue != null) issues.add(lightIssue);

      var required = const <LandmarkPoint>[];
      var allPose = const <PosePoint>[];
      FaceSnapshot? face;
      double? faceWidth;

      switch (step) {
        case CaptureStep.fullBody:
          if (faces.length > 1) issues.add(CaptureIssue.multiplePeople);
          if (poses.isEmpty) {
            issues.add(CaptureIssue.noPerson);
          } else {
            required = _evaluate(poses.first, upright);
            allPose = _allPoints(poses.first, upright);
            if (required.any((p) => !p.ok)) issues.add(CaptureIssue.outOfFrame);
          }
        case CaptureStep.face:
          if (faces.isEmpty) {
            issues.add(CaptureIssue.noFace);
          } else if (faces.length > 1) {
            issues.add(CaptureIssue.multiplePeople);
          } else {
            face = _snapshot(faces.first, upright);
            faceWidth = face.box.width;
            if (!_insideSafeZone(face.box)) issues.add(CaptureIssue.outOfFrame);
            if (faceWidth < _config.faceMinWidthFraction) {
              issues.add(CaptureIssue.faceTooFar);
            }
          }
        case CaptureStep.hands:
          if (_handsActive) {
            final handIssue = handSideIssue(
              choice: _sideChoice(),
              hands: hands,
              framesMirrored: _framesMirrored(),
              requireBoth: _config.requireBothHands,
            );
            if (handIssue != null) issues.add(handIssue);
            if (hands.any((h) => h.points.any((p) => !_insidePoint(p)))) {
              issues.add(CaptureIssue.outOfFrame);
            }
          }
        case CaptureStep.feet:
          break; // lighting only: no model tracks feet without the upper body
      }

      return FrameCheck(
        issues: issues,
        at: now,
        uprightSize: upright,
        rotationDegrees: rotation,
        pose: allPose,
        faceCount: faces.length,
        face: face,
        hands: hands,
        overlay: buildOverlay(
          pose: allPose,
          hands: hands,
          choice: _sideChoice(),
          framesMirrored: _framesMirrored(),
        ),
        quality: assessQuality(
          config: _config,
          step: step,
          issues: issues,
          luma: luma,
          sharpness: _sharpness,
          motion: _motion,
          subjectFraction: faceWidth ?? _bodyHeight(required),
        ),
        metrics: FrameMetrics(
          step: step,
          luma: luma,
          faces: faces.length,
          poses: poses.length,
          landmarks: required,
          issues: issues,
          analysesPerSecond: _runTimes.length,
          rotationDegrees: rotation,
          faceWidthFraction: faceWidth,
          hands: hands.length,
          handTracking: _handsActive,
        ),
      );
    } finally {
      _busy = false;
    }
  }

  /// Must run before the first await: it reads the camera buffer.
  void _sampleQuality(CameraImage image, DateTime now) {
    if (now.difference(_lastQualitySample) < _config.qualitySampleInterval) {
      return;
    }
    _lastQualitySample = now;
    final plane = image.planes.first;
    final isBgra = InputImageFormatValue.fromRawValue(image.format.raw) ==
        InputImageFormat.bgra8888;
    final thumb = isBgra
        ? LumaThumb.fromBgra(plane.bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: plane.bytesPerRow)
        : LumaThumb.fromLumaPlane(plane.bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: plane.bytesPerRow);
    _sharpness = thumb.sharpness;
    _motion = thumb.motionFrom(_prevThumb);
    _prevThumb = thumb;
  }

  /// Head-to-ankle span as a share of the frame height, or null when a
  /// required point was not found.
  double? _bodyHeight(List<LandmarkPoint> required) {
    if (required.isEmpty || required.any((p) => p.y < 0)) return null;
    final ys = [for (final p in required) p.y];
    return ys.reduce((a, b) => a > b ? a : b) -
        ys.reduce((a, b) => a < b ? a : b);
  }

  RgbaFrame _handImage(CameraImage image, int rotation) {
    final plane = image.planes.first;
    final nv21 = InputImageFormatValue.fromRawValue(image.format.raw) ==
        InputImageFormat.nv21;
    return downscaleToRgba(
      plane.bytes,
      nv21: nv21,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      rotationDegrees: rotation,
    );
  }

  /// Never throws: three failures in a row switch hand tracking off for the
  /// rest of the step, and the step checks lighting only.
  Future<List<HandSnapshot>> _detectHands(RgbaFrame frame) async {
    try {
      final hands = await NativeBridge.detectHands(frame)
          .timeout(const Duration(seconds: 1));
      _handFailures = 0;
      return hands;
    } catch (e) {
      _handFailures++;
      debugPrint('movement_capture: hand tracking failed ($_handFailures): $e');
      if (_handFailures >= 3) {
        _handsActive = false;
        debugPrint(
            'movement_capture: hand tracking switched off for this step');
      }
      return const [];
    }
  }

  @override
  Future<void> close() async {
    try {
      await _pose?.close();
    } catch (_) {}
    try {
      await _faces?.close();
    } catch (_) {}
    if (step.usesHands) await NativeBridge.closeHands();
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

  bool _insidePoint(Offset p) {
    final inset = _config.safeZoneInset;
    return p.dx >= inset &&
        p.dx <= 1 - inset &&
        p.dy >= inset &&
        p.dy <= 1 - inset;
  }

  bool _insideSafeZone(Rect r) {
    final inset = _config.safeZoneInset;
    return r.left >= inset &&
        r.top >= inset &&
        r.right <= 1 - inset &&
        r.bottom <= 1 - inset;
  }

  FaceSnapshot _snapshot(Face f, Size upright) {
    Offset norm(int x, int y) => Offset(x / upright.width, y / upright.height);
    return FaceSnapshot(
      box: _normalisedRect(f.boundingBox, upright),
      headEulerX: f.headEulerAngleX,
      headEulerY: f.headEulerAngleY,
      headEulerZ: f.headEulerAngleZ,
      landmarks: {
        for (final e in f.landmarks.entries)
          if (e.value case final lm?)
            e.key.name: norm(lm.position.x, lm.position.y),
      },
      contours: {
        for (final e in f.contours.entries)
          if (e.value case final c? when c.points.isNotEmpty)
            e.key.name: [for (final p in c.points) norm(p.x, p.y)],
      },
    );
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
