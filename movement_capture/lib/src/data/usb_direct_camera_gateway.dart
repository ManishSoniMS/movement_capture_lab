import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show
        CameraImageData,
        CameraImageFormat,
        CameraImagePlane,
        ImageFormatGroup;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/camera_gateway.dart';
import '../domain/config.dart';
import 'native_bridge.dart';

/// Width x height the USB mode search aims for, per plugin preset. Matches
/// what the `camera` plugin means by each preset.
CameraFrameSize usbTargetSize(ResolutionPreset p) => switch (p) {
      ResolutionPreset.low => const CameraFrameSize(320, 240),
      ResolutionPreset.medium => const CameraFrameSize(720, 480),
      ResolutionPreset.high => const CameraFrameSize(1280, 720),
      ResolutionPreset.veryHigh => const CameraFrameSize(1920, 1080),
      ResolutionPreset.ultraHigh => const CameraFrameSize(3840, 2160),
      ResolutionPreset.max => const CameraFrameSize(3840, 2160),
    };

/// Wraps an NV21 buffer as a [CameraImage] so the analyzers stay unchanged.
CameraImage nv21CameraImage(Uint8List bytes, int width, int height) =>
    CameraImage.fromPlatformInterface(CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
      width: width,
      height: height,
      planes: [
        CameraImagePlane(bytes: bytes, bytesPerRow: width),
      ],
    ));

/// [CameraGateway] that drives a UVC webcam directly through the plugin's
/// native `UsbDirectCamera` (libuvc), for devices whose Camera2 does not list
/// it. Preview is a Flutter texture; frames arrive as NV21 on an EventChannel
/// with one frame in flight at a time.
class UsbDirectCameraGateway implements CameraGateway {
  UsbDirectCameraGateway({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.config,
    required this.analysisInterval,
    required Future<String> Function() newRecordingPath,
  }) : _newRecordingPath = newRecordingPath;

  final String deviceName;
  final int vendorId;
  final int productId;
  final MovementCaptureConfig config;
  final Duration analysisInterval;
  final Future<String> Function() _newRecordingPath;

  final StreamController<CameraLost> _lost = StreamController.broadcast();
  StreamSubscription<dynamic>? _frameSub;
  StreamSubscription<dynamic>? _eventSub;
  void Function(CameraImage)? _onFrame;

  CameraFrameSize _size = const CameraFrameSize(0, 0);
  int? _textureId;
  bool _initialized = false;
  bool _streaming = false;
  bool _recording = false;
  bool _disposed = false;
  String? _recordingPath;

  /// Flutter texture id for `Texture(textureId:)`. Null before [initialize].
  int? get textureId => _textureId;

  /// Preview width / height of the chosen mode.
  double get aspectRatio =>
      _size.height == 0 ? 16 / 9 : _size.width / _size.height;

  /// Modes the camera offers, for diagnostics.
  List<String> supportedModes = const [];

  /// Mode in use, e.g. "mjpeg".
  String? format;

  @override
  Future<void> initialize() async {
    final target = usbTargetSize(config.resolution);
    _eventSub = NativeBridge.usbEvents.listen(_onEvent, onError: (_) {});
    try {
      final r = await NativeBridge.usbOpen(
        deviceName: deviceName,
        width: target.width,
        height: target.height,
        analysisIntervalMs: analysisInterval.inMilliseconds,
        previewSurface: config.usbPreviewSurface.name,
      );
      _textureId = (r['textureId'] as num?)?.toInt();
      _size = CameraFrameSize(
          (r['width'] as num?)?.toInt() ?? 0, (r['height'] as num?)?.toInt() ?? 0);
      format = r['format'] as String?;
      supportedModes = [
        for (final m in (r['modes'] as List?) ?? const []) '$m',
      ];
      debugPrint('movement_capture: usb direct open $_size $format '
          'texture=$_textureId modes=${supportedModes.length}');
      _initialized = _textureId != null;
    } on PlatformException catch (e) {
      await _cleanup();
      throw CameraGatewayException(e.message ?? e.code,
          code: e.code, permissionDenied: e.code == 'permission');
    } catch (e) {
      await _cleanup();
      throw CameraGatewayException('$e', code: 'usbOpen');
    }
    if (!_initialized) {
      await _cleanup();
      throw const CameraGatewayException('no texture', code: 'usbOpen');
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map || _lost.isClosed) return;
    final type = event['type'];
    switch (type) {
      case 'detached':
        if (event['deviceName'] == deviceName ||
            (event['vendorId'] == vendorId && event['productId'] == productId)) {
          _lost.add(const CameraLost(CameraLostReason.unplugged));
        }
      case 'error':
        _lost.add(CameraLost(CameraLostReason.error, '${event['message']}'));
      case 'noFrames':
        _lost.add(const CameraLost(CameraLostReason.noFrames));
    }
  }

  @override
  CameraFrameSize get frameSize => _size;

  @override
  int get sensorOrientation => 0;

  /// USB cameras are not rotated by the screen; `cameraRotationDegrees`
  /// (config) supplies the rotation.
  @override
  int get previewOrientationDegrees => 0;

  @override
  bool get isInitialized => _initialized && !_disposed;

  @override
  bool get isStreaming => _streaming;

  @override
  bool get isRecording => _recording;

  @override
  String? get activeRecordingPath => _recording ? _recordingPath : null;

  void _handleFrame(dynamic event) {
    if (event is! Map) {
      NativeBridge.usbFrameDone();
      return;
    }
    final bytes = event['bytes'];
    final w = (event['width'] as num?)?.toInt() ?? _size.width;
    final h = (event['height'] as num?)?.toInt() ?? _size.height;
    final sink = _onFrame;
    if (bytes is Uint8List && sink != null && !_disposed) {
      try {
        sink(nv21CameraImage(bytes, w, h));
      } catch (e) {
        debugPrint('movement_capture: usb frame handler failed: $e');
      }
    }
    // The bytes were copied into Dart, so the native buffer is free again.
    NativeBridge.usbFrameDone();
  }

  Future<void> _ensureStream() async {
    _frameSub ??= NativeBridge.usbFrames.listen(_handleFrame, onError: (_) {});
    if (!_streaming) {
      await NativeBridge.usbStartStream();
      _streaming = true;
    }
  }

  CameraGatewayException _wrap(Object e, String code) => e is PlatformException
      ? CameraGatewayException(e.message ?? e.code, code: e.code)
      : CameraGatewayException('$e', code: code);

  @override
  Future<void> startImageStream(void Function(CameraImage) onFrame) async {
    _onFrame = onFrame;
    try {
      await _ensureStream();
    } catch (e) {
      throw _wrap(e, 'usbStartStream');
    }
  }

  @override
  Future<void> stopImageStream() async {
    _onFrame = null;
    _streaming = false;
    await NativeBridge.usbStopStream();
  }

  @override
  Future<void> startRecording({void Function(CameraImage)? onFrame}) async {
    try {
      final path = await _newRecordingPath();
      if (onFrame != null) {
        _onFrame = onFrame;
        await _ensureStream();
      } else {
        await stopImageStream();
      }
      _recordingPath = path;
      await NativeBridge.usbStartRecording(path);
      _recording = true;
    } catch (e) {
      _recordingPath = null;
      throw _wrap(e, 'usbStartRecording');
    }
  }

  @override
  Future<String> stopRecording() async {
    final expected = _recordingPath;
    try {
      final path = await NativeBridge.usbStopRecording();
      return path.isEmpty ? (expected ?? '') : path;
    } catch (e) {
      throw _wrap(e, 'usbStopRecording');
    } finally {
      _recording = false;
      _recordingPath = null;
    }
  }

  @override
  Stream<CameraLost> get lost => _lost.stream;

  Future<void> _cleanup() async {
    await _frameSub?.cancel();
    _frameSub = null;
    await _eventSub?.cancel();
    _eventSub = null;
    _onFrame = null;
    _streaming = false;
    await NativeBridge.usbClose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    await _cleanup();
    _recording = false;
    await _lost.close();
  }
}
