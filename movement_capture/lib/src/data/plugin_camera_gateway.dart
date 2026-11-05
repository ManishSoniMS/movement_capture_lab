import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/camera_gateway.dart';

/// [CameraGateway] backed by the `camera` plugin (`CameraController`).
/// Same preset, no audio and image format per platform as before the gateway
/// existed.
class PluginCameraGateway implements CameraGateway {
  PluginCameraGateway(
    CameraDescription description,
    ResolutionPreset resolution, {
    bool isIOS = false,
  })  : _description = description,
        _controller = CameraController(
          description,
          resolution,
          enableAudio: false,
          imageFormatGroup:
              isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
        );

  final CameraDescription _description;
  final CameraController _controller;
  final StreamController<CameraLost> _lost = StreamController.broadcast();
  bool _listening = false;

  static const Set<String> _permissionCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  static const Map<DeviceOrientation, int> _degrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// For the preview widget.
  CameraController get controller => _controller;

  CameraGatewayException _wrap(CameraException e) => CameraGatewayException(
        e.description ?? e.code,
        code: e.code,
        permissionDenied: _permissionCodes.contains(e.code),
      );

  @override
  Future<void> initialize() async {
    try {
      await _controller.initialize(); // may show the permission prompt
    } on CameraException catch (e) {
      throw _wrap(e);
    }
    _controller.addListener(_onValue);
    _listening = true;
  }

  void _onValue() {
    if (_controller.value.hasError && !_lost.isClosed) {
      _lost.add(CameraLost(
          CameraLostReason.error, _controller.value.errorDescription ?? ''));
    }
  }

  @override
  CameraFrameSize get frameSize {
    final size = _controller.value.previewSize;
    return size == null
        ? const CameraFrameSize(0, 0)
        : CameraFrameSize(size.width.round(), size.height.round());
  }

  @override
  int get sensorOrientation => _description.sensorOrientation;

  /// The orientation CameraPreview uses to rotate the Android preview. Must
  /// match it exactly, or the analysed frames are rotated wrongly.
  @override
  int get previewOrientationDegrees {
    final v = _controller.value;
    final o = v.isRecordingVideo
        ? (v.recordingOrientation ?? v.deviceOrientation)
        : (v.previewPauseOrientation ??
            v.lockedCaptureOrientation ??
            v.deviceOrientation);
    return _degrees[o] ?? 0;
  }

  @override
  bool get isStreaming => _controller.value.isStreamingImages;

  @override
  bool get isRecording => _controller.value.isRecordingVideo;

  @override
  String? get activeRecordingPath => null;

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  Future<void> startImageStream(void Function(CameraImage) onFrame) async {
    try {
      await _controller.startImageStream(onFrame);
    } on CameraException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> stopImageStream() async {
    try {
      await _controller.stopImageStream();
    } on CameraException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> startRecording({void Function(CameraImage)? onFrame}) async {
    try {
      await _controller.startVideoRecording(onAvailable: onFrame);
    } on CameraException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<String> stopRecording() async {
    try {
      return (await _controller.stopVideoRecording()).path;
    } on CameraException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Stream<CameraLost> get lost => _lost.stream;

  @override
  Future<void> dispose() async {
    if (_listening) _controller.removeListener(_onValue);
    _listening = false;
    try {
      await _controller.dispose();
    } catch (e) {
      debugPrint('movement_capture: camera dispose failed: $e');
    }
    await _lost.close();
  }
}
