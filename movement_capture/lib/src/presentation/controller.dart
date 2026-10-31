import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/file_capture_storage.dart';
import '../data/mlkit_frame_analyzer.dart';
import '../domain/body_sides.dart';
import '../domain/camera_choice.dart';
import '../domain/capture_issue.dart';
import '../domain/capture_state.dart';
import '../domain/capture_step.dart';
import '../domain/capture_storage.dart';
import '../domain/config.dart';
import '../domain/frame_analyzer.dart';
import '../domain/frame_metrics.dart';
import '../domain/landmark_track.dart';
import '../domain/quality_timer.dart';
import '../domain/result.dart';
import '../domain/camera_quality.dart';
import '../domain/quality_status.dart';
import '../domain/quality_summary.dart';
import '../domain/uploader.dart';
import 'serial_queue.dart';
import 'step_uploads.dart';

/// Owned by the capture screen's State. Its lifetime IS the widget's lifetime.
///
/// Concurrency rule: every operation that opens, closes, records with or
/// releases the camera runs through [_queue], one at a time. Public methods
/// and timer/frame callbacks enqueue; code already inside the queue calls the
/// `...Impl` methods directly and never enqueues again.
///
/// Uploads run through [StepUploads], a separate queue, so they never block
/// the camera while the next step is filmed.
class MovementCaptureController extends ChangeNotifier {
  MovementCaptureController({
    required this.config,
    required MovementUploader uploader,
    CaptureStorage storage = const FileCaptureStorage(),
    FrameAnalyzerFactory analyzerFactory = MlKitFrameAnalyzer.new,
    this.onCameraChanged,
    bool lowMemoryDevice = false,
  })  : _storage = storage,
        _analyzerFactory = analyzerFactory,
        _quality = QualityTimer(grace: config.violationGrace),
        _statusTracker = QualityStatusTracker(config.qualityHold),
        steps = List.unmodifiable(config.effectiveSteps),
        sessionId = _newSessionId(),
        analysisInterval =
            config.effectiveAnalysisInterval(lowMemoryDevice: lowMemoryDevice) {
    _uploads = StepUploads(
      uploader: uploader,
      storage: storage,
      onChanged: _onUploadsChanged,
    );
  }

  static String _newSessionId() {
    final r = Random.secure();
    return List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  final MovementCaptureConfig config;
  final CaptureStorage _storage;
  final FrameAnalyzerFactory _analyzerFactory;
  final QualityTimer _quality;
  final QualityStatusTracker _statusTracker;
  final SerialQueue _queue = SerialQueue();
  late final StepUploads _uploads;

  /// Steps of this session, in order.
  final List<CaptureStep> steps;

  /// Sent with every step's upload.
  final String sessionId;

  /// Minimum time between analysed frames for this session.
  final Duration analysisInterval;

  /// Fired only when the operator picks a camera from the list.
  final void Function(CameraDescription camera)? onCameraChanged;

  /// Latest analysis numbers, for the debug overlay.
  final ValueNotifier<FrameMetrics?> metrics = ValueNotifier(null);

  /// What the status area shows (in frame? video quality?), held steady for
  /// `qualityHold`. Null while no frames are being analysed.
  final ValueNotifier<QualityStatus?> status = ValueNotifier(null);

  /// True when the active camera's resolution or measured frame rate is below
  /// the configured minimum. Checked once each time a camera opens.
  final ValueNotifier<bool> cameraWeak = ValueNotifier(false);
  FrameRateMeter? _fpsMeter;
  bool _cameraSizeOk = true;

  CaptureState _state = const Initializing();
  CaptureState get state => _state;

  CameraController? _camera;
  CameraController? get camera => _camera;
  FrameAnalyzer? _analyzer;

  List<CameraChoice> _choices = const [];
  List<CameraChoice> get cameras => _choices;
  CameraChoice? _selected;
  CameraChoice? get selectedCamera => _selected;

  int _stepIndex = 0;

  /// 0-based index of the current step.
  int get stepIndex => _stepIndex;
  int get stepCount => steps.length;
  CaptureStep get currentStep => steps[_stepIndex];

  CaptureStep? _lastSaved;

  /// The step recorded just before the current one (for "Saved: …").
  CaptureStep? get lastSavedStep => _lastSaved;

  final Set<CaptureStep> _skipped = {};
  bool _sessionFinished = false;

  /// One entry per configured step.
  List<CaptureStepResult> get results => [
        for (final s in steps)
          CaptureStepResult(
            step: s,
            analysisId: _uploads.analysisIdFor(s),
            skipped: _skipped.contains(s),
            retakes: _retakes[s] ?? 0,
            sideChoice: sideChoiceFor(s),
          ),
      ];

  final Map<CaptureStep, SideChoice> _sideChoices = {};

  /// Sides chosen for [step]; [SideChoice.both] until the person picks.
  SideChoice sideChoiceFor(CaptureStep step) =>
      _sideChoices[step] ?? SideChoice.both;

  /// True while the "which hands / feet?" question is on screen. Start is
  /// not offered until it is answered.
  bool get awaitingSideChoice =>
      config.offerSideChoice &&
      !_sessionFinished &&
      currentStep.hasSides &&
      !_sideChoices.containsKey(currentStep);

  /// Operator or user picked the sides for the current step.
  void chooseSides(SideChoice choice) {
    if (_disposed || !awaitingSideChoice) return;
    _sideChoices[currentStep] = choice;
    notifyListeners();
  }

  /// True if quitting now would throw away a recording, a clip under review,
  /// or uploads that haven't finished.
  bool get hasUnsavedWork {
    final s = _state;
    if (s is CountingDown || s is Recording || s is Reviewing) return true;
    if (s is Finishing || s is FinishFailed) return true;
    return _uploads.hasUnfinished;
  }

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// True when no USB camera is connected and a built-in camera is in use.
  bool get usingTabletFallback =>
      _selected != null &&
      !_selected!.isExternal &&
      !_choices.any((c) => c.isExternal);

  /// The camera list may be opened in these states only.
  bool get canChangeCamera =>
      !_starting && !_busyTransition && _stateAllowsCameraChange;

  /// Whether "Skip this step" may be offered right now (UI).
  bool get canSkipCurrentStep =>
      !_sessionFinished &&
      config.skippableSteps.contains(currentStep) &&
      canChangeCamera;

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
  bool _purgedAtStart = false;
  bool _frameSeenThisPhase = false;
  bool _liveChecks = true;
  int _restarts = 0;

  Timer? _countdownTimer;
  Timer? _maxDurationTimer;
  Timer? _ticker;
  Timer? _frameWatchdog;
  final Stopwatch _recordClock = Stopwatch();

  Duration _recordedDuration = Duration.zero;
  DateTime? _capturedAtUtc;
  LandmarkTrack? _track;

  MovementClip? _pendingClip; // recorded, waiting for review
  final Map<CaptureStep, int> _retakes = {};
  final List<QualitySample> _qualitySamples = [];

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

  /// The orientation CameraPreview uses to rotate the Android preview.
  /// Must match it exactly, or the analysed frames are rotated wrongly.
  static DeviceOrientation _previewOrientation(CameraValue v) =>
      v.isRecordingVideo
          ? (v.recordingOrientation ?? v.deviceOrientation)
          : (v.previewPauseOrientation ??
              v.lockedCaptureOrientation ??
              v.deviceOrientation);

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
    if (awaitingSideChoice) return;
    final s = _state;
    if (s is Checking && !s.armed) {
      _quality.restartGoodWindow(); // fresh stability window from now
      _setState(Checking(issue: s.issue, armed: true));
    }
  }

  /// Operator tapped "Skip this step".
  Future<void> skipStep() => _serial(() async {
        if (_disposed || _sessionFinished) return;
        if (!config.skippableSteps.contains(currentStep)) return;
        if (!_stateAllowsCameraChange) return;
        _skipped.add(currentStep);
        _newPhase();
        _cancelAllTimers();
        await _advanceImpl(saved: false);
      });

  /// Review: "Use this video".
  Future<void> acceptReview() => _serial(() async {
        if (_disposed || _state is! Reviewing) return;
        final clip = _pendingClip;
        _pendingClip = null;
        _qualitySamples.clear();
        if (clip == null) return;
        _uploads.enqueue(clip);
        await _advanceImpl(saved: true); // reopens the camera if needed
      });

  /// Review: "Record again".
  Future<void> retakeStep() => _serial(() async {
        if (_disposed || _state is! Reviewing) return;
        final clip = _pendingClip;
        _pendingClip = null;
        _qualitySamples.clear();
        if (clip != null) await _deleteClipFiles(clip);
        _retakes[currentStep] = (_retakes[currentStep] ?? 0) + 1;
        _restarts = 0;
        await _startImpl(); // same step, same camera, waiting for Start
      });

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

  /// "Retry" on the final screen: re-sends failed uploads.
  void retryFailedUploads() {
    if (_disposed || _state is! FinishFailed) return;
    _uploads.retryFailed();
    _updateFinishState();
  }

  /// App went to the background (paused/hidden): release the camera. Uploads
  /// keep running. Never call this for `inactive`.
  Future<void> suspend() => _serial(() async {
        if (_disposed || _sessionFinished) return;
        if (_camera == null) return;
        _newPhase();
        _cancelAllTimers();
        await _stopAndDeleteActiveRecording();
        await _releaseCamera();
        _restarts = 0;
        _suspended = true;
        _setState(const Initializing());
      });

  /// App came back: reopen if [suspend] released the camera, or retry if the
  /// user just came back from Settings after camera access was off.
  Future<void> resume() => _serial(() async {
        if (_disposed || _sessionFinished) return;
        final s = _state;
        final cameFromSettings = s is CameraUnavailable &&
            s.reason == CameraFailure.permissionDenied;
        if (!_suspended && !cameFromSettings) return;
        _suspended = false;
        await _releaseCamera();
        await _startImpl();
      });

  @override
  void dispose() {
    _disposed = true;
    _cancelAllTimers();
    _uploads.cancelAll(); // don't make teardown wait for uploads
    unawaited(_serial(_teardownImpl));
    metrics.dispose();
    status.dispose();
    cameraWeak.dispose();
    super.dispose();
  }

  // ------------------------------------------------- queued implementations

  Future<void> _startImpl() async {
    if (_disposed || _sessionFinished) return;
    _starting = true;
    _setState(const Initializing());
    try {
      if (!_purgedAtStart) {
        // Once per session: a later purge would delete earlier steps' files
        // that are still waiting to upload.
        await _storage.purgeAll(); // leftovers from a crash or kill
        _purgedAtStart = true;
      }
      final choices = await _enumerate();
      if (_disposed) return;
      final stepChoice = _firstOfKind(choices, config.stepCameras[currentStep]);
      final choice = pickDefaultCamera(
        choices,
        preferredId:
            _selected?.id ?? stepChoice?.id ?? config.preferredCameraId,
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
    if (_disposed || _sessionFinished || !_stateAllowsCameraChange) return;
    if (choice.id == _selected?.id && _camera != null && _state is Checking) {
      return; // already in use
    }
    await _switchCameraImpl(choice);
    if (!_disposed && _camera != null) {
      onCameraChanged?.call(choice.description);
    }
  }

  /// Closes the current camera and opens [choice] for the current step.
  Future<void> _switchCameraImpl(CameraChoice choice) async {
    _starting = true;
    _setState(const Initializing());
    try {
      _newPhase();
      _cancelAllTimers();
      await _releaseCamera();
      _restarts = 0;
      await _open(choice);
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

  CameraChoice? _firstOfKind(List<CameraChoice> choices, CameraKind? kind) {
    if (kind == null) return null;
    for (final c in choices) {
      if (c.kind == kind) return c;
    }
    return null;
  }

  FrameAnalyzer _newAnalyzer() => _analyzerFactory(config,
      step: currentStep,
      rotationDegrees: _analysisRotation,
      interval: analysisInterval,
      sideChoice: () => sideChoiceFor(currentStep),
      framesMirrored: () => _fileMirrored);

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
    final size = cam.value.previewSize;
    _cameraSizeOk = size == null ||
        cameraIsGoodEnough(
            config: config,
            width: size.width.round(),
            height: size.height.round(),
            fps: config.minCameraFps);
    cameraWeak.value = !_cameraSizeOk;
    _fpsMeter = FrameRateMeter(const Duration(seconds: 2));
    _analyzer = _newAnalyzer();
    await _beginChecking();
  }

  int _analysisRotation() {
    final choice = _selected;
    final cam = _camera;
    if (choice == null || cam == null) return config.cameraRotationDegrees ?? 0;
    return analysisRotationDegrees(
      kind: choice.kind,
      sensorOrientation: choice.description.sensorOrientation,
      screenDegrees: _orientationDegrees[_previewOrientation(cam.value)] ?? 0,
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
    var left = config.effectiveCountdown.inSeconds;
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
      _track = _liveChecks && currentStep.recordsLandmarks
          ? LandmarkTrack(sessionId: sessionId, step: currentStep)
          : null;
      _qualitySamples.clear();
      final total = config.durationFor(currentStep);
      _recordClock
        ..reset()
        ..start();
      _setState(Recording(
        elapsed: Duration.zero,
        total: total,
        liveChecks: _liveChecks,
      ));
      final recordingEpoch = _epoch;
      _maxDurationTimer = Timer(total, () {
        if (_transitionQueued || _disposed) return;
        _transitionQueued = true;
        unawaited(_serial(() => _finishRecordingImpl(recordingEpoch)));
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_state is! Recording) return;
        final e = _recordClock.elapsed;
        _setState(Recording(
          elapsed: e > total ? total : e,
          total: total,
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
      _track = null;
      _qualitySamples.clear();
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
    File? video;
    File? landmarks;
    try {
      _stopRecordingTimers();
      _recordedDuration = _recordClock.elapsed;
      final raw = await cam.stopVideoRecording();
      debugPrint('movement_capture: raw file at ${raw.path}');
      _newPhase();
      video = await _storage.adopt(raw.path);
      final track = _track;
      _track = null;
      if (track != null && !track.isEmpty) {
        landmarks = await _storage
            .writeLandmarks(jsonEncode(track.toJson(mirrored: _fileMirrored)));
      }
    } on CameraException catch (e) {
      debugPrint('movement_capture: finish failed ${e.code}');
      _busyTransition = false;
      await _failImpl(CameraFailure.other);
      return;
    } on FileSystemException catch (e) {
      debugPrint('movement_capture: saving the clip failed $e');
      if (video != null) await _storage.deletePath(video.path);
      _busyTransition = false;
      await _failImpl(CameraFailure.other);
      return;
    } finally {
      _busyTransition = false;
    }
    final savedVideo = video;
    if (_disposed) return; // teardown purges the files

    final kind = _selected?.kind ?? CameraKind.external;
    final clip = MovementClip(
      file: savedVideo,
      landmarksFile: landmarks,
      duration: _recordedDuration,
      resolution: config.resolution,
      capturedAtUtc: _capturedAtUtc ?? DateTime.now().toUtc(),
      metadata: Map.unmodifiable(config.metadata),
      platform: _isIOS ? 'ios' : 'android',
      cameraKind: kind.name,
      fileMirrored: _fileMirrored,
      liveChecks: _liveChecks,
      sessionId: sessionId,
      step: currentStep,
      stepIndex: _stepIndex,
      stepCount: steps.length,
      retakes: _retakes[currentStep] ?? 0,
      reviewed: config.reviewBeforeUpload,
      sideChoice: sideChoiceFor(currentStep),
    );

    if (!config.reviewBeforeUpload) {
      _uploads.enqueue(clip);
      await _advanceImpl(saved: true);
      return;
    }

    _pendingClip = clip;
    final fileMirrored = _fileMirrored;
    await _releaseCamera(); // the player needs the memory; reopened after
    if (_disposed) return; // teardown deletes the pending clip
    _setState(Reviewing(
      video: savedVideo,
      quality: QualitySummary.from(
        _qualitySamples,
        durationMs: _recordClock.elapsedMilliseconds,
        config: config,
      ),
      cameraKind: kind,
      fileMirrored: fileMirrored,
    ));
  }

  /// Moves to the next step, or finishes the session after the last one.
  Future<void> _advanceImpl({required bool saved}) async {
    if (saved) _lastSaved = currentStep;
    _restarts = 0;
    if (_stepIndex + 1 >= steps.length) {
      await _finishSessionImpl();
      return;
    }
    _stepIndex++;

    final wanted = config.stepCameras[currentStep];
    if (wanted != null && _selected?.kind != wanted) {
      final target = _firstOfKind(await _enumerate(), wanted);
      if (target != null) {
        await _switchCameraImpl(target);
        return;
      }
    }
    if (_camera == null) {
      await _startImpl();
      return;
    }
    // Frames from the old step's analyzer may still arrive; _onFrame ignores
    // them because the analyzer is no longer current (T37).
    final old = _analyzer;
    _analyzer = _newAnalyzer();
    try {
      await old?.close();
    } catch (_) {}
    await _beginChecking();
  }

  Future<void> _finishSessionImpl() async {
    _sessionFinished = true;
    _newPhase();
    _cancelAllTimers();
    await _releaseCamera(); // not needed for uploads
    _updateFinishState();
  }

  // --------------------------------------------------------------- uploads

  void _onUploadsChanged() {
    if (_disposed) return;
    if (_sessionFinished) {
      _updateFinishState();
    } else {
      notifyListeners();
    }
  }

  void _updateFinishState() {
    if (_disposed || !_sessionFinished) return;
    if (_uploads.hasPending) {
      _setState(Finishing(_uploads.progress));
    } else if (_uploads.failedCount > 0) {
      _setState(FinishFailed(_uploads.failedCount));
    } else {
      _setState(const SessionComplete());
    }
  }

  // ---------------------------------------------------------------- frames

  bool get _fileMirrored => _isIOS && _selected?.kind == CameraKind.front;

  void _onFrame(CameraImage image) {
    _frameSeenThisPhase = true;
    final fps = _fpsMeter?.add(DateTime.now());
    if (fps != null) {
      cameraWeak.value = !_cameraSizeOk || fps < config.minCameraFps;
    }
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
          _disposed ||
          !identical(analyzer, _analyzer)) {
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
    final reading = check.quality;
    if (reading != null) {
      final shown = _statusTracker.feed(reading, check.at);
      if (shown != status.value) status.value = shown;
    }
    // Poor quality only stops the capture when the host asked for that.
    final r = _quality.feed(
        config.blockOnPoorQuality ? check.topIssue : null, check.at);

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
        _recordSample(check);
        if (reading != null) {
          _qualitySamples.add(QualitySample(
            tMs: _recordClock.elapsedMilliseconds,
            inFrame: reading.inFrame,
            problems: reading.problems,
          ));
        }
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

  void _recordSample(FrameCheck check) {
    final track = _track;
    if (track == null) return;
    final t = _recordClock.elapsedMilliseconds;
    switch (track.step) {
      case CaptureStep.fullBody:
        track.addPose(
          tMs: t,
          pose: check.pose,
          faceCount: check.faceCount,
          image: check.uprightSize,
          rotationDegrees: check.rotationDegrees,
        );
      case CaptureStep.face:
        track.addFace(
          tMs: t,
          face: check.face,
          faceCount: check.faceCount,
          image: check.uprightSize,
          rotationDegrees: check.rotationDegrees,
        );
      case CaptureStep.hands:
        track.addHands(
          tMs: t,
          hands: check.hands,
          framesMirrored: _fileMirrored,
          image: check.uprightSize,
          rotationDegrees: check.rotationDegrees,
        );
      case CaptureStep.feet:
        break;
    }
  }

  void _onCameraValue() {
    final cam = _camera;
    if (cam == null || !cam.value.hasError) return;
    if (_state is CameraUnavailable || _sessionFinished) return;
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
        _track = null; // a partial track would mislead the server
        _qualitySamples.clear();
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
      _track = null;
      await _stopAndDeleteActiveRecording();
      await _releaseCamera();
      _restarts = 0;
      _setState(CameraUnavailable(reason));
    } finally {
      _failing = false;
    }
  }

  Future<void> _releaseCamera() async {
    if (!_disposed) _clearStatus();
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

  Future<void> _deleteClipFiles(MovementClip clip) async {
    await _storage.deletePath(clip.file.path);
    final landmarks = clip.landmarksFile;
    if (landmarks != null) await _storage.deletePath(landmarks.path);
  }

  Future<void> _teardownImpl() async {
    _newPhase();
    _cancelAllTimers();
    await _stopAndDeleteActiveRecording();
    await _releaseCamera();
    final pending = _pendingClip;
    _pendingClip = null;
    if (pending != null) await _deleteClipFiles(pending);
    _uploads.cancelAll();
    await _uploads.deleteAllFiles();
    await _storage.purgeAll();
  }

  void _setState(CaptureState next) {
    if (_disposed) return;
    _state = next;
    // The status only makes sense while frames are being analysed.
    final analysing = next is Checking ||
        next is CountingDown ||
        (next is Recording && next.liveChecks);
    if (!analysing) _clearStatus();
    notifyListeners();
  }

  void _clearStatus() {
    _statusTracker.reset();
    if (status.value != null) status.value = null;
  }
}
