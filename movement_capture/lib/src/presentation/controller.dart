import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/file_capture_storage.dart';
import '../data/mlkit_frame_analyzer.dart';
import '../domain/camera_choice.dart';
import '../domain/capture_issue.dart';
import '../domain/capture_state.dart';
import '../domain/capture_storage.dart';
import '../domain/config.dart';
import '../domain/frame_analyzer.dart';
import '../domain/frame_metrics.dart';
import '../domain/quality_timer.dart';
import '../domain/uploader.dart';
import 'serial_queue.dart';

/// Owned by the capture screen's State. Its lifetime IS the widget's lifetime.
///
/// Concurrency rule: every operation that opens, closes, records with or
/// releases the camera runs through [_queue], one at a time. Public methods
/// and timer/frame callbacks enqueue; code already inside the queue calls the
/// `...Impl` methods directly and never enqueues again.
class MovementCaptureController extends ChangeNotifier {
  MovementCaptureController({
    required this.config,
    required MovementUploader uploader,
    CaptureStorage storage = const FileCaptureStorage(),
    FrameAnalyzer Function(MovementCaptureConfig config,
            {required int Function() rotationDegrees})
        analyzerFactory = MlKitFrameAnalyzer.new,
    this.onCameraChanged,
  })  : _uploader = uploader,
        _storage = storage,
        _analyzerFactory = analyzerFactory,
        _quality = QualityTimer(grace: config.violationGrace);

  final MovementCaptureConfig config;
  final MovementUploader _uploader;
  final CaptureStorage _storage;
  final FrameAnalyzer Function(MovementCaptureConfig,
      {required int Function() rotationDegrees}) _analyzerFactory;
  final QualityTimer _quality;
  final SerialQueue _queue = SerialQueue();

  /// Fired only when the operator picks a camera from the list.
  final void Function(CameraDescription camera)? onCameraChanged;

  /// Latest analysis numbers, for the debug overlay.
  final ValueNotifier<FrameMetrics?> metrics = ValueNotifier(null);

  CaptureState _state = const Initializing();
  CaptureState get state => _state;

  CameraController? _camera;
  CameraController? get camera => _camera;
  FrameAnalyzer? _analyzer;

  List<CameraChoice> _choices = const [];
  List<CameraChoice> get cameras => _choices;
  CameraChoice? _selected;
  CameraChoice? get selectedCamera => _selected;

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// True when no USB camera is connected and a built-in camera is in use.
  bool get usingTabletFallback =>
      _selected != null &&
      !_selected!.isExternal &&
      !_choices.any((c) => c.isExternal);

  /// The camera list may be opened in these states only.
  bool get canChangeCamera =>
      !_starting && !_busyTransition && _stateAllowsCameraChange;

  bool get _stateAllowsCameraChange => switch (_state) {
        Checking(armed: false) => true,
        NeedsOperator() => true,
        CameraUnavailable() => true,
        _ => false,
      };

  // `_epoch` changes with every phase, so ML results computed for an older
  // phase are thrown away.
  int _epoch = 0;
  int _countdownId = 0;
  bool _busyTransition = false;
  bool _transitionQueued = false;
  bool _starting = false;
  bool _failing = false;
  bool _disposed = false;
  bool _suspended = false;
  bool _frameSeenThisPhase = false;
  bool _liveChecks = true;
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

  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // ------------------------------------------------------------- queueing

  /// Enqueues [operation]. Unexpected errors are logged, never thrown, so one
  /// failure cannot block later operations or crash the app.
  Future<void> _serial(Future<void> Function() operation) {
    return _queue.run(operation).catchError((Object e, StackTrace s) {
      debugPrint('movement_capture: operation failed: $e\n$s');
    });
  }

  /// For timers and callbacks: fail only if still in the same phase (and
  /// still on the same camera, when given).
  void _requestFail(
    CameraFailure reason, {
    int? epoch,
    CameraController? camera,
  }) {
    unawaited(_serial(() async {
      if (_disposed) return;
      if (epoch != null && epoch != _epoch) return;
      if (camera != null && !identical(camera, _camera)) return;
      await _failImpl(reason);
    }));
  }

  // ---------------------------------------------------------------- public

  /// Lists cameras and opens the best one: the current/preferred camera if
  /// still connected, else the first USB camera, else front, else back.
  Future<void> start() => _serial(_startImpl);

  /// Operator picked a camera from the list.
  Future<void> selectCamera(CameraChoice choice) =>
      _serial(() => _selectImpl(choice));

  /// Re-reads the camera list (e.g. after plugging in a webcam). Read-only,
  /// so it does not need the queue. Does not change the camera in use.
  Future<void> refreshCameras() async {
    if (_disposed) return;
    try {
      await _enumerate();
    } on CameraException catch (e) {
      debugPrint('movement_capture: refresh failed ${e.code}');
    }
  }

  /// Operator tapped "Start recording". Touches no camera, so not queued.
  void startRequested() {
    final s = _state;
    if (s is Checking && !s.armed) {
      _quality.restartGoodWindow(); // fresh stability window from now
      _setState(Checking(issue: s.issue, armed: true));
    }
  }

  /// Operator tapped "Try again" on the NeedsOperator panel.
  Future<void> operatorRetry() => _serial(() async {
        if (_disposed || _state is! NeedsOperator) return;
        _restarts = 0;
        await _beginChecking(armed: true);
      });

  /// Re-lists cameras and reopens: the same camera if still connected,
  /// otherwise the default rule (a missing USB camera falls back to built-in).
  Future<void> retryCamera() => _serial(() async {
        if (_disposed || _state is! CameraUnavailable) return;
        await _releaseCamera();
        await _startImpl();
      });

  Future<void> retryUpload() => _serial(() async {
        if (_disposed || _state is! UploadFailed) return;
        await _uploadVideo();
      });

  /// App went to the background (paused/hidden): drop everything except an
  /// upload. Never call this for `inactive`.
  Future<void> suspend() => _serial(() async {
        if (_disposed) return;
        final s = _state;
        if (s is Uploading || s is UploadFailed || s is Completed) return;
        if (_camera == null) return;
        _newPhase();
        _cancelAllTimers();
        await _stopAndDeleteActiveRecording();
        await _releaseCamera();
        _restarts = 0;
        _suspended = true;
        _setState(const Initializing());
      });

  /// App came back: reopen only if [suspend] released the camera.
  Future<void> resume() => _serial(() async {
        if (_disposed || !_suspended) return;
        _suspended = false;
        await _startImpl();
      });

  @override
  void dispose() {
    _disposed = true;
    _cancelAllTimers();
    _uploadCancellation?.cancel(); // don't make teardown wait for an upload
    unawaited(_serial(_teardownImpl));
    metrics.dispose();
    super.dispose();
  }

  // ------------------------------------------------- queued implementations

  Future<void> _startImpl() async {
    if (_disposed) return;
    _starting = true;
    _setState(const Initializing());
    try {
      await _storage.purgeAll(); // leftovers from a crash or kill
      final choices = await _enumerate();
      if (_disposed) return;
      final choice = pickDefaultCamera(
        choices,
        preferredId: _selected?.id ?? config.preferredCameraId,
      );
      if (choice == null) {
        _setState(const CameraUnavailable(CameraFailure.noCamera));
        return;
      }
      await _open(choice);
    } on CameraException catch (e) {
      debugPrint('movement_capture: init failed ${e.code} ${e.description}');
      await _releaseCamera();
      _setState(CameraUnavailable(_failureFor(e)));
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _selectImpl(CameraChoice choice) async {
    if (_disposed || !_stateAllowsCameraChange) return;
    if (choice.id == _selected?.id && _camera != null && _state is Checking) {
      return; // already in use
    }
    _starting = true;
    _setState(const Initializing());
    try {
      _newPhase();
      _cancelAllTimers();
      await _releaseCamera();
      _restarts = 0;
      await _storage.purgeAll(); // safe: nothing is recording
      await _open(choice);
      if (!_disposed) onCameraChanged?.call(choice.description);
    } on CameraException catch (e) {
      debugPrint('movement_capture: switch to ${choice.id} failed ${e.code}');
      await _releaseCamera();
      _setState(CameraUnavailable(_failureFor(e)));
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // ---------------------------------------------------------- camera setup

  Future<List<CameraChoice>> _enumerate() async {
    final cams = await availableCameras();
    debugPrint('movement_capture: cameras = '
        '${cams.map((c) => '${c.name}/${c.lensDirection.name}/${c.sensorOrientation}°').join(', ')}');
    _choices = buildCameraChoices(cams);
    if (!_disposed) notifyListeners();
    return _choices;
  }

  /// Throws CameraException on failure; callers handle it.
  Future<void> _open(CameraChoice choice) async {
    _selected = choice;
    final cam = CameraController(
      choice.description,
      config.resolution,
      enableAudio: false,
      imageFormatGroup:
          _isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );
    _camera = cam;
    await cam.initialize(); // may show the permission prompt
    // Nothing else can release `cam` meanwhile (serial queue), but the screen
    // may have been closed while the prompt was up.
    if (_disposed || !identical(_camera, cam)) {
      if (identical(_camera, cam)) _camera = null;
      try {
        await cam.dispose();
      } catch (_) {}
      return;
    }
    cam.addListener(_onCameraValue);
    _analyzer = _analyzerFactory(config, rotationDegrees: _analysisRotation);
    await _beginChecking();
  }

  int _analysisRotation() {
    final choice = _selected;
    final cam = _camera;
    if (choice == null || cam == null) return config.cameraRotationDegrees;
    return analysisRotationDegrees(
      kind: choice.kind,
      sensorOrientation: choice.description.sensorOrientation,
      screenDegrees: _orientationDegrees[cam.value.deviceOrientation] ?? 0,
      configRotation: config.cameraRotationDegrees,
      isIOS: _isIOS,
    );
  }

  CameraFailure _failureFor(CameraException e) =>
      _permissionCodes.contains(e.code)
          ? CameraFailure.permissionDenied
          : CameraFailure.other;

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
      await _failImpl(CameraFailure.other);
    }
  }

  void _beginCountdown() {
    var left = config.countdown.inSeconds;
    if (left < 1) left = 1;
    if (left > 10) left = 10;
    final id = ++_countdownId;
    _setState(CountingDown(left));
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (id != _countdownId || _disposed) {
        t.cancel();
        return;
      }
      left--;
      if (left <= 0) {
        t.cancel();
        _countdownTimer = null;
        if (_transitionQueued) return;
        _transitionQueued = true;
        unawaited(_serial(() => _startRecordingImpl(id)));
      } else {
        _setState(CountingDown(left));
      }
    });
  }

  void _cancelCountdown(CaptureIssue issue) {
    _countdownId++; // invalidates any queued start for the old countdown
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _quality.restartGoodWindow();
    _setState(Checking(issue: issue, armed: true));
  }

  Future<void> _startRecordingImpl(int countdownId) async {
    _transitionQueued = false;
    final cam = _camera;
    if (_disposed ||
        cam == null ||
        countdownId != _countdownId ||
        _state is! CountingDown) {
      return;
    }
    _busyTransition = true;
    try {
      // startVideoRecording(onAvailable:) starts its own image stream and
      // throws if one is already running.
      if (cam.value.isStreamingImages) await cam.stopImageStream();
      _newPhase();
      _liveChecks = true;
      try {
        await cam.startVideoRecording(onAvailable: _onFrame);
      } on CameraException catch (e) {
        if (!config.allowRecordingWithoutLiveChecks) rethrow;
        // Some devices cannot record and send frames at the same time.
        debugPrint('movement_capture: recording with frames failed '
            '(${e.code}); recording without live checks');
        _liveChecks = false;
        await cam.startVideoRecording();
      }
      if (_disposed) return; // teardown (queued next) deletes the file
      _capturedAtUtc = DateTime.now().toUtc();
      _recordClock
        ..reset()
        ..start();
      _setState(Recording(
        elapsed: Duration.zero,
        total: config.maxDuration,
        liveChecks: _liveChecks,
      ));
      final recordingEpoch = _epoch;
      _maxDurationTimer = Timer(config.maxDuration, () {
        if (_transitionQueued || _disposed) return;
        _transitionQueued = true;
        unawaited(_serial(() => _finishRecordingImpl(recordingEpoch)));
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_state is! Recording) return;
        final e = _recordClock.elapsed;
        _setState(Recording(
          elapsed: e > config.maxDuration ? config.maxDuration : e,
          total: config.maxDuration,
          liveChecks: _liveChecks,
        ));
      });
      if (_liveChecks) _armWatchdog();
    } on CameraException catch (e) {
      debugPrint('movement_capture: start recording failed ${e.code}');
      _busyTransition = false;
      await _failImpl(config.allowRecordingWithoutLiveChecks
          ? CameraFailure.other
          : CameraFailure.streamUnsupported);
    } finally {
      _busyTransition = false;
    }
  }

  Future<void> _abortRecordingImpl(CaptureIssue issue, int epoch) async {
    _transitionQueued = false;
    final cam = _camera;
    if (_disposed || cam == null || epoch != _epoch || _state is! Recording) {
      return;
    }
    _busyTransition = true;
    try {
      _stopRecordingTimers();
      final raw = await cam.stopVideoRecording();
      await _storage.deletePath(raw.path);
      _restarts++;
    } on CameraException catch (e) {
      debugPrint('movement_capture: abort failed ${e.code}');
      _busyTransition = false;
      await _failImpl(CameraFailure.other);
      return;
    } finally {
      _busyTransition = false;
    }
    if (_disposed) return;

    if (_restarts > config.maxRestarts) {
      _newPhase();
      _setState(NeedsOperator(issue));
      return; // no stream runs now; "Try again" restarts it
    }
    await _beginChecking(interruptedBy: issue, armed: true);
  }

  Future<void> _finishRecordingImpl(int epoch) async {
    _transitionQueued = false;
    final cam = _camera;
    if (_disposed || cam == null || epoch != _epoch || _state is! Recording) {
      return;
    }
    _busyTransition = true;
    try {
      _stopRecordingTimers();
      _recordedDuration = _recordClock.elapsed;
      final raw = await cam.stopVideoRecording();
      debugPrint('movement_capture: raw file at ${raw.path}');
      _newPhase();
      _video = await _storage.adopt(raw.path);
    } on CameraException catch (e) {
      debugPrint('movement_capture: finish failed ${e.code}');
      _busyTransition = false;
      await _failImpl(CameraFailure.other);
      return;
    } finally {
      _busyTransition = false;
    }
    if (_disposed) return; // teardown deletes _video
    await _releaseCamera(); // not needed for the upload
    await _uploadVideo();
  }

  Future<void> _uploadVideo() async {
    final file = _video;
    if (file == null || _disposed) return;
    final cancellation = UploadCancellation();
    _uploadCancellation = cancellation;
    _setState(const Uploading(0));
    final kind = _selected?.kind ?? CameraKind.external;
    try {
      final id = await _uploader.upload(
        MovementClip(
          file: file,
          duration: _recordedDuration,
          resolution: config.resolution,
          capturedAtUtc: _capturedAtUtc ?? DateTime.now().toUtc(),
          metadata: Map.unmodifiable(config.metadata),
          platform: _isIOS ? 'ios' : 'android',
          cameraKind: kind.name,
          fileMirrored: _isIOS && kind == CameraKind.front,
          liveChecks: _liveChecks,
        ),
        onProgress: (p) {
          if (cancellation.isCancelled || _state is! Uploading) return;
          _setState(Uploading(p < 0 ? 0 : (p > 1 ? 1 : p)));
        },
        cancellation: cancellation,
      );
      if (cancellation.isCancelled || _disposed) return;
      if (id.isEmpty) throw StateError('Uploader returned an empty id');
      await _storage.deletePath(file.path);
      _video = null;
      _setState(Completed(id));
    } catch (e) {
      if (cancellation.isCancelled || _disposed) return;
      debugPrint('movement_capture: upload failed $e');
      _setState(const UploadFailed());
    }
  }

  // ---------------------------------------------------------------- frames

  void _onFrame(CameraImage image) {
    _frameSeenThisPhase = true;
    final analyzer = _analyzer;
    if (analyzer == null || _busyTransition || _transitionQueued || _disposed) {
      return;
    }
    final epoch = _epoch;
    analyzer.analyze(image).then((check) {
      if (check == null ||
          epoch != _epoch ||
          _busyTransition ||
          _transitionQueued ||
          _disposed) {
        return;
      }
      _onCheck(check);
    }).catchError((Object error) {
      if (error is UnsupportedFrameFormat) {
        debugPrint('movement_capture: $error');
        _requestFail(CameraFailure.streamUnsupported, epoch: epoch);
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
      case Recording(liveChecks: true):
        if (r.confirmedBad && !_transitionQueued) {
          _transitionQueued = true;
          final issue = r.lastIssue!;
          final epoch = _epoch;
          unawaited(_serial(() => _abortRecordingImpl(issue, epoch)));
        }
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
    _requestFail(CameraFailure.other, camera: cam); // e.g. webcam unplugged
  }

  /// No frame within 3 s of a phase starting: during recording, continue
  /// without live checks (if allowed); otherwise the camera can't be checked.
  void _armWatchdog() {
    _frameWatchdog?.cancel();
    final epoch = _epoch;
    _frameWatchdog = Timer(const Duration(seconds: 3), () {
      if (epoch != _epoch || _frameSeenThisPhase || _disposed) return;
      final s = _state;
      if (s is Recording && config.allowRecordingWithoutLiveChecks) {
        debugPrint('movement_capture: no frames while recording; '
            'continuing without live checks');
        _liveChecks = false;
        _setState(Recording(
          elapsed: s.elapsed,
          total: s.total,
          liveChecks: false,
        ));
        return;
      }
      debugPrint(
          'movement_capture: no frames for 3 s in ${_state.runtimeType}');
      _requestFail(CameraFailure.streamUnsupported, epoch: epoch);
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
    _countdownId++;
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
      await _storage.deletePath(raw.path);
    } catch (_) {
      // purgeAll removes anything left behind
    }
  }

  Future<void> _failImpl(CameraFailure reason) async {
    if (_disposed || _failing) return;
    _failing = true;
    try {
      _newPhase();
      _cancelAllTimers();
      await _stopAndDeleteActiveRecording();
      await _releaseCamera();
      await _storage.purgeAll();
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

  Future<void> _teardownImpl() async {
    _newPhase();
    _cancelAllTimers();
    await _stopAndDeleteActiveRecording();
    await _releaseCamera();
    final video = _video;
    _video = null;
    if (video != null) await _storage.deletePath(video.path);
    await _storage.purgeAll();
  }

  void _setState(CaptureState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }
}
