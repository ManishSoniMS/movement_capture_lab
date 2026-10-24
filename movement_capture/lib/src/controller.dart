import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'capture_issue.dart';
import 'capture_state.dart';
import 'config.dart';
import 'frame_quality_analyzer.dart';
import 'quality_timer.dart';
import 'storage.dart';
import 'uploader.dart';

/// Owned by the capture screen's State. Its lifetime IS the widget's lifetime.
class MovementCaptureController extends ChangeNotifier {
  MovementCaptureController({
    required this.config,
    required MovementUploader uploader,
  })  : _uploader = uploader,
        _quality = QualityTimer(grace: config.violationGrace);

  final MovementCaptureConfig config;
  final MovementUploader _uploader;
  final QualityTimer _quality;

  /// Latest analysis numbers, for the debug overlay.
  final ValueNotifier<FrameMetrics?> metrics = ValueNotifier(null);

  CaptureState _state = const Initializing();
  CaptureState get state => _state;

  CameraController? _camera;
  CameraController? get camera => _camera;
  FrameQualityAnalyzer? _analyzer;

  // `_epoch` changes with every phase, so ML results computed for an older
  // phase are thrown away.
  int _epoch = 0;
  bool _busyTransition = false;
  bool _starting = false;
  bool _failing = false;
  bool _disposed = false;
  bool _tornDown = false;
  bool _frameSeenThisPhase = false;
  int _restarts = 0;

  Timer? _countdownTimer;
  Timer? _maxDurationTimer;
  Timer? _ticker;
  Timer? _frameWatchdog;
  final Stopwatch _recordClock = Stopwatch();

  File? _video;
  Duration _recordedDuration = Duration.zero;
  DateTime? _capturedAtUtc;
  UploadCancellation? _uploadCancellation;

  static const Set<String> _permissionCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  // ---------------------------------------------------------------- public

  Future<void> start() async {
    if (_disposed || _starting) return;
    _starting = true;
    _setState(const Initializing());
    try {
      await MovementCaptureStorage.purgeAll(); // leftovers from a crash or kill
      final cameras = await availableCameras();
      final external = cameras
          .where((c) => c.lensDirection == CameraLensDirection.external)
          .toList();
      if (external.isEmpty) {
        debugPrint('movement_capture: no external camera. Found: '
            '${cameras.map((c) => '${c.name}/${c.lensDirection}').join(', ')}');
        _setState(const CameraUnavailable(CameraFailure.notConnected));
        return;
      }

      final cam = CameraController(
        external.first,
        config.resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      _camera = cam;
      await cam.initialize();
      if (_disposed) {
        await cam.dispose();
        return;
      }
      cam.addListener(_onCameraValue);
      _analyzer = FrameQualityAnalyzer(config);
      await _beginChecking();
    } on CameraException catch (e) {
      debugPrint('movement_capture: init failed ${e.code} ${e.description}');
      await _releaseCamera();
      _setState(CameraUnavailable(_permissionCodes.contains(e.code)
          ? CameraFailure.permissionDenied
          : CameraFailure.other));
    } finally {
      _starting = false;
    }
  }

  /// Operator tapped "Start recording".
  void startRequested() {
    final s = _state;
    if (s is Checking && !s.armed) {
      _quality.restartGoodWindow(); // fresh stability window from now
      _setState(Checking(issue: s.issue, armed: true));
    }
  }

  /// Operator tapped "Try again" on the NeedsOperator panel.
  Future<void> operatorRetry() async {
    if (_state is! NeedsOperator) return;
    _restarts = 0;
    await _beginChecking(armed: true);
  }

  Future<void> retryCamera() async {
    if (_state is! CameraUnavailable) return;
    await _releaseCamera();
    await start();
  }

  Future<void> retryUpload() async {
    if (_state is! UploadFailed) return;
    await _uploadVideo();
  }

  /// App went to background or inactive: drop everything except an upload.
  Future<void> suspend() async {
    if (_disposed) return;
    final s = _state;
    if (s is Uploading || s is UploadFailed || s is Completed) return;
    if (_camera == null) return;
    _newPhase();
    _cancelAllTimers();
    await _stopAndDeleteActiveRecording();
    await _releaseCamera();
    _restarts = 0;
    _setState(const Initializing());
  }

  Future<void> resume() async {
    if (_disposed) return;
    if (_state is Initializing && _camera == null) await start();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown());
    metrics.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- phases

  Future<void> _beginChecking({
    CaptureIssue? interruptedBy,
    bool armed = false,
  }) async {
    final cam = _camera;
    if (cam == null || _disposed) return;
    _newPhase();
    _setState(Checking(
      issue: interruptedBy,
      armed: armed,
      interrupted: interruptedBy != null,
    ));
    try {
      if (!cam.value.isStreamingImages) await cam.startImageStream(_onFrame);
      _armWatchdog();
    } on CameraException catch (e) {
      debugPrint('movement_capture: image stream failed ${e.code}');
      await _fail(CameraFailure.other);
    }
  }

  void _beginCountdown() {
    var left = config.countdown.inSeconds;
    if (left < 1) left = 1;
    if (left > 10) left = 10;
    _setState(CountingDown(left));
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      left--;
      if (left <= 0) {
        t.cancel();
        _countdownTimer = null;
        unawaited(_startRecording());
      } else {
        _setState(CountingDown(left));
      }
    });
  }

  void _cancelCountdown(CaptureIssue issue) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _quality.restartGoodWindow();
    _setState(Checking(issue: issue, armed: true));
  }

  Future<void> _startRecording() async {
    final cam = _camera;
    if (cam == null || _state is! CountingDown || _busyTransition) return;
    _busyTransition = true;
    try {
      // startVideoRecording(onAvailable:) starts its own image stream and
      // throws if one is already running.
      if (cam.value.isStreamingImages) await cam.stopImageStream();
      _newPhase();
      await cam.startVideoRecording(onAvailable: _onFrame);
      _capturedAtUtc = DateTime.now().toUtc();
      _recordClock
        ..reset()
        ..start();
      _setState(Recording(elapsed: Duration.zero, total: config.maxDuration));
      _maxDurationTimer =
          Timer(config.maxDuration, () => unawaited(_finishRecording()));
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_state is! Recording) return;
        final e = _recordClock.elapsed;
        _setState(Recording(
          elapsed: e > config.maxDuration ? config.maxDuration : e,
          total: config.maxDuration,
        ));
      });
      _armWatchdog();
    } on CameraException catch (e) {
      debugPrint('movement_capture: start recording failed ${e.code}');
      _busyTransition = false;
      await _fail(CameraFailure.other);
      return;
    } finally {
      _busyTransition = false;
    }
  }

  Future<void> _abortRecording(CaptureIssue issue) async {
    final cam = _camera;
    if (cam == null || _busyTransition || _state is! Recording) return;
    _busyTransition = true;
    try {
      _stopRecordingTimers();
      final raw = await cam.stopVideoRecording();
      await MovementCaptureStorage.deletePath(raw.path);
      _restarts++;
    } on CameraException catch (e) {
      debugPrint('movement_capture: abort failed ${e.code}');
      _busyTransition = false;
      await _fail(CameraFailure.other);
      return;
    } finally {
      _busyTransition = false;
    }

    if (_restarts > config.maxRestarts) {
      _newPhase();
      _setState(NeedsOperator(issue));
      return; // no stream runs now; "Try again" restarts it
    }
    await _beginChecking(interruptedBy: issue, armed: true);
  }

  Future<void> _finishRecording() async {
    final cam = _camera;
    if (cam == null || _busyTransition || _state is! Recording) return;
    _busyTransition = true;
    try {
      _stopRecordingTimers();
      _recordedDuration = _recordClock.elapsed;
      final raw = await cam.stopVideoRecording();
      debugPrint('movement_capture: raw file at ${raw.path}');
      _newPhase();
      _video = await MovementCaptureStorage.adopt(raw);
    } on CameraException catch (e) {
      debugPrint('movement_capture: finish failed ${e.code}');
      _busyTransition = false;
      await _fail(CameraFailure.other);
      return;
    } finally {
      _busyTransition = false;
    }
    await _releaseCamera(); // not needed for the upload
    await _uploadVideo();
  }

  Future<void> _uploadVideo() async {
    final file = _video;
    if (file == null || _disposed) return;
    final cancellation = UploadCancellation();
    _uploadCancellation = cancellation;
    _setState(const Uploading(0));
    try {
      final id = await _uploader.upload(
        MovementClip(
          file: file,
          duration: _recordedDuration,
          resolution: config.resolution,
          capturedAtUtc: _capturedAtUtc ?? DateTime.now().toUtc(),
          metadata: Map.unmodifiable(config.metadata),
        ),
        onProgress: (p) {
          if (cancellation.isCancelled || _state is! Uploading) return;
          _setState(Uploading(p < 0 ? 0 : (p > 1 ? 1 : p)));
        },
        cancellation: cancellation,
      );
      if (cancellation.isCancelled) return;
      if (id.isEmpty) throw StateError('Uploader returned an empty id');
      await MovementCaptureStorage.deletePath(file.path);
      _video = null;
      _setState(Completed(id));
    } catch (e) {
      if (cancellation.isCancelled) return;
      debugPrint('movement_capture: upload failed $e');
      _setState(const UploadFailed());
    }
  }

  // ---------------------------------------------------------------- frames

  void _onFrame(CameraImage image) {
    _frameSeenThisPhase = true;
    final analyzer = _analyzer;
    if (analyzer == null || _busyTransition || _disposed) return;
    final epoch = _epoch;
    analyzer.analyze(image).then((check) {
      if (check == null || epoch != _epoch || _busyTransition || _disposed) {
        return;
      }
      _onCheck(check);
    }).catchError((Object error) {
      if (error is UnsupportedFrameFormat) {
        debugPrint('movement_capture: $error');
        unawaited(_fail(CameraFailure.streamUnsupported));
      }
      // Other errors (e.g. detector closed during teardown) are ignored.
    });
  }

  void _onCheck(FrameCheck check) {
    metrics.value = check.metrics;
    final r = _quality.feed(check.topIssue, check.at);

    switch (_state) {
      case final Checking s:
        if (r.confirmedBad) {
          if (s.issue != r.lastIssue) {
            _setState(Checking(
              issue: r.lastIssue,
              armed: s.armed,
              interrupted: s.interrupted,
            ));
          }
        } else if (s.issue != null && r.goodFor >= config.violationGrace) {
          _setState(Checking(armed: s.armed)); // clear the alert
        }
        final current = _state;
        if (current is Checking &&
            current.armed &&
            current.issue == null &&
            r.goodFor >= config.stableBeforeStart) {
          _beginCountdown();
        }
      case CountingDown():
        if (r.confirmedBad) _cancelCountdown(r.lastIssue!);
      case Recording():
        if (r.confirmedBad) unawaited(_abortRecording(r.lastIssue!));
      default:
        break;
    }
  }

  void _onCameraValue() {
    final cam = _camera;
    if (cam == null || !cam.value.hasError) return;
    final s = _state;
    if (s is CameraUnavailable || s is Uploading || s is Completed) return;
    debugPrint('movement_capture: camera error ${cam.value.errorDescription}');
    unawaited(_fail(CameraFailure.other)); // e.g. webcam unplugged
  }

  /// If no frame arrives within 3 s of a phase starting, frames are not
  /// available in this mode (see lab check V2).
  void _armWatchdog() {
    _frameWatchdog?.cancel();
    final epoch = _epoch;
    _frameWatchdog = Timer(const Duration(seconds: 3), () {
      if (epoch == _epoch && !_frameSeenThisPhase && !_disposed) {
        debugPrint('movement_capture: no frames for 3 s in ${_state.runtimeType}');
        unawaited(_fail(CameraFailure.streamUnsupported));
      }
    });
  }

  // --------------------------------------------------------------- helpers

  void _newPhase() {
    _epoch++;
    _quality.reset();
    _frameSeenThisPhase = false;
    _frameWatchdog?.cancel();
    _frameWatchdog = null;
  }

  void _stopRecordingTimers() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _ticker?.cancel();
    _ticker = null;
    _recordClock.stop();
  }

  void _cancelAllTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _stopRecordingTimers();
    _frameWatchdog?.cancel();
    _frameWatchdog = null;
  }

  Future<void> _stopAndDeleteActiveRecording() async {
    final cam = _camera;
    if (cam == null || !cam.value.isRecordingVideo) return;
    try {
      final raw = await cam.stopVideoRecording();
      await MovementCaptureStorage.deletePath(raw.path);
    } catch (_) {
      // purgeAll removes anything left behind
    }
  }

  Future<void> _fail(CameraFailure reason) async {
    if (_disposed || _failing) return;
    _failing = true;
    try {
      _newPhase();
      _cancelAllTimers();
      await _stopAndDeleteActiveRecording();
      await _releaseCamera();
      await MovementCaptureStorage.purgeAll();
      _restarts = 0;
      _setState(CameraUnavailable(reason));
    } finally {
      _failing = false;
    }
  }

  Future<void> _releaseCamera() async {
    _frameWatchdog?.cancel();
    final cam = _camera;
    _camera = null;
    final analyzer = _analyzer;
    _analyzer = null;
    if (cam != null) {
      cam.removeListener(_onCameraValue);
      try {
        if (cam.value.isStreamingImages) await cam.stopImageStream();
      } catch (_) {}
      try {
        await cam.dispose();
      } catch (_) {}
    }
    try {
      await analyzer?.close();
    } catch (_) {}
    if (!_disposed) notifyListeners(); // preview disappears
  }

  Future<void> _teardown() async {
    if (_tornDown) return;
    _tornDown = true;
    _newPhase();
    _cancelAllTimers();
    _uploadCancellation?.cancel();
    await _stopAndDeleteActiveRecording();
    await _releaseCamera();
    final video = _video;
    _video = null;
    if (video != null) await MovementCaptureStorage.deletePath(video.path);
    await MovementCaptureStorage.purgeAll();
  }

  void _setState(CaptureState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }
}
