import 'dart:async';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../domain/native_support_info.dart';
import '../domain/support_report.dart';
import 'native_bridge.dart';

/// Gathers facts with timeouts and hands them to [evaluateSupport].
/// Never throws.
abstract final class SupportChecker {
  static bool _mlKitConfirmed = false;

  static Future<SupportReport> run(SupportRequirements requirements) async {
    final platform = kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'android',
            TargetPlatform.iOS => 'ios',
            final other => other.name,
          };
    if (platform != 'android' && platform != 'ios') {
      return evaluateSupport(
        platform: platform,
        native: null,
        cameras: null,
        mlKitAvailable: false,
        requirements: requirements,
      );
    }

    NativeSupportInfo? native;
    String? nativeError;
    try {
      native = await NativeBridge.supportInfo()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      nativeError = '$e';
    }

    List<CameraDescription>? cameras;
    String? cameraError;
    try {
      // Listing cameras never asks for permission on Android or iOS.
      cameras = await availableCameras().timeout(const Duration(seconds: 5));
    } catch (e) {
      cameraError = '$e';
    }

    var mlKit = _mlKitConfirmed;
    String? mlKitError;
    if (!mlKit) {
      try {
        mlKit = await _probeMlKit(platform == 'ios')
            .timeout(const Duration(seconds: 15));
        _mlKitConfirmed = mlKit;
      } catch (e) {
        mlKitError = '$e';
        mlKit = false;
      }
    }

    return evaluateSupport(
      platform: platform,
      native: native,
      cameras: cameras,
      mlKitAvailable: mlKit,
      requirements: requirements,
      nativeError: nativeError,
      cameraError: cameraError,
      mlKitError: mlKitError,
    );
  }

  /// Runs both detectors once on a blank grey image. Proves the native ML Kit
  /// libraries and bundled models load on this device.
  static Future<bool> _probeMlKit(bool isIOS) async {
    const w = 256, h = 256;
    final bytes = isIOS ? Uint8List(w * h * 4) : Uint8List(w * h * 3 ~/ 2);
    bytes.fillRange(0, bytes.length, 128);
    final input = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: const Size(256, 256),
        rotation: InputImageRotation.rotation0deg,
        format: isIOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
        bytesPerRow: isIOS ? w * 4 : w,
      ),
    );
    final pose = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.single),
    );
    final face = FaceDetector(options: FaceDetectorOptions());
    try {
      await pose.processImage(input);
      await face.processImage(input);
      return true;
    } finally {
      try {
        await pose.close();
      } catch (_) {}
      try {
        await face.close();
      } catch (_) {}
    }
  }
}
