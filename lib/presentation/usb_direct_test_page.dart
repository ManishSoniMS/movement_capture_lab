import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uvccamera/src/uvccamera_platform_interface.dart'; // ignore: implementation_imports
import 'package:uvccamera/uvccamera.dart';
import 'package:video_player/video_player.dart';

import '../data/uploaders.dart';

/// One USB device as Android itself reports it (lab native channel).
@immutable
class _UsbInfo {
  const _UsbInfo({
    required this.deviceName,
    required this.name,
    required this.vendorId,
    required this.productId,
    required this.isVideo,
    required this.interfaces,
    required this.maxPowerMa,
    required this.hasPermission,
  });

  factory _UsbInfo.fromMap(Map<Object?, Object?> m) => _UsbInfo(
        deviceName: m['deviceName']! as String,
        name: m['name']! as String,
        vendorId: m['vendorId']! as int,
        productId: m['productId']! as int,
        isVideo: m['isVideo']! as bool,
        interfaces: [for (final i in m['interfaces']! as List) i! as String],
        maxPowerMa: m['maxPowerMa']! as int,
        hasPermission: m['hasPermission']! as bool,
      );

  /// Path such as `/dev/bus/usb/001/027`. Changes on every replug.
  final String deviceName;
  final String name;
  final int vendorId;
  final int productId;
  final bool isVideo;

  /// `class/subclass` per interface, hex. A webcam shows `0E/01` and `0E/02`.
  final List<String> interfaces;
  final int maxPowerMa;
  final bool hasPermission;

  /// Stable id across replugs, hex: `0C45:0261`.
  String get key => '${_hex4(vendorId)}:${_hex4(productId)}';
}

String _hex4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');

/// Frame area each preset asks the plugin for (from `UvcCameraNativeMethodCallHandler.java:52`).
const _presetAsk = <UvcCameraResolutionPreset, String>{
  UvcCameraResolutionPreset.min: 'smallest size',
  UvcCameraResolutionPreset.low: '640x480 = 307200 px',
  UvcCameraResolutionPreset.medium: '1280x720 = 921600 px',
  UvcCameraResolutionPreset.high: '1920x1080 = 2073600 px',
  UvcCameraResolutionPreset.max: 'largest size',
};

/// LAB ONLY, TEMPORARY (kiosk-08 Part A): go/no-go test for talking to a USB
/// webcam directly over UVC, without Android's camera system.
///
/// Lists real cameras (video-class interface) apart from other USB devices,
/// asks for CAMERA and then USB permission, opens the preview at a preset the
/// operator picks, lists the modes the camera offers, records clips and copies
/// them to the `inspection/` folder for `adb pull`. Tools to tell "no frames"
/// from "frames not drawn": a coloured backing behind the texture, the widget
/// size, a quick clip played back in-app, and the app's own native log. Every
/// error and plugin event is shown on screen. Removed in Part B.
class UsbDirectTestPage extends StatefulWidget {
  const UsbDirectTestPage({super.key});

  @override
  State<UsbDirectTestPage> createState() => _UsbDirectTestPageState();
}

class _UsbDirectTestPageState extends State<UsbDirectTestPage> {
  static const _channel = MethodChannel('lab/camera_diagnostics');
  static const _recordSeconds = 10;
  static const _quickSeconds = 3;

  final _log = <String>[];
  final _subs = <StreamSubscription<Object?>>[];
  final _camSubs = <StreamSubscription<Object?>>[];

  List<_UsbInfo> _usb = const [];
  bool? _cameraGranted;
  UvcCameraController? _controller;

  /// True only after `initialize()` really succeeded. The preview widget and
  /// `textureId` are never touched before this.
  bool _ready = false;
  String? _openKey;
  UvcCameraResolutionPreset? _openPreset;
  final _openWatch = Stopwatch();
  bool? _supported;
  bool _busy = false;
  bool _recording = false;
  int _remaining = 0;
  Timer? _ticker;
  String? _result;

  /// What the camera offers, read after open (empty = not read / failed).
  List<UvcCameraMode> _modes = const [];

  /// Last camera and preset, for the Reopen button after a drop.
  _UsbInfo? _lastCam;
  UvcCameraResolutionPreset? _lastPreset;
  String? _dropHint;

  /// `true`/`false` from the build switch, `null` = not set (default on).
  bool? _impeller;
  bool _impellerKnown = false;

  VideoPlayerController? _clip;
  String? _nativeLog;

  @override
  void initState() {
    super.initState();
    _subs.add(UvcCamera.deviceEventStream.listen(
      _onDeviceEvent,
      onError: (Object e) => _note('device stream error: $e'),
    ));
    unawaited(_refresh());
    unawaited(_readImpeller());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final s in [..._subs, ..._camSubs]) {
      unawaited(s.cancel());
    }
    final c = _controller;
    _controller = null;
    _ready = false;
    if (c != null) unawaited(_safeDispose(c));
    unawaited(_clip?.dispose());
    super.dispose();
  }

  void _note(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    debugPrint('[usb-direct] $line');
    if (!mounted) return;
    setState(() => _log.insert(0, '$t  $line'));
  }

  /// Logs an error with everything useful; the stack goes to the console.
  void _noteError(String what, Object e, [StackTrace? st]) {
    if (e is PlatformException) {
      _note('$what: PlatformException code=${e.code} message=${e.message} '
          'details=${e.details}');
    } else {
      _note('$what: ${e.runtimeType}: $e');
    }
    if (st != null) debugPrintStack(stackTrace: st, label: what);
  }

  Future<void> _readImpeller() async {
    try {
      final v = await _channel.invokeMethod<bool>('impellerEnabled');
      if (!mounted) return;
      setState(() {
        _impeller = v;
        _impellerKnown = true;
      });
    } catch (e) {
      _note('impeller flag unreadable: $e');
    }
  }

  /// A camera disconnect while open: log how long it ran and what it was
  /// doing, close cleanly, and do NOT reopen (use the Reopen button).
  void _onDeviceEvent(UvcCameraDeviceEvent e) {
    _note('device event: ${e.type.name} ${e.device.name}');
    final gone = e.type == UvcCameraDeviceEventType.detached ||
        e.type == UvcCameraDeviceEventType.disconnected;
    final open = _openKey;
    final key = '${_hex4(e.device.vendorId)}:${_hex4(e.device.productId)}';
    if (gone && open != null && key == open) {
      final secs = (_openWatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
      final mode = _controller?.value.previewMode;
      final what = _recording ? 'recording' : 'previewing';
      final modeText = mode == null
          ? '?'
          : '${mode.frameWidth}x${mode.frameHeight} ${mode.frameFormat.name}';
      _note('open camera dropped after $secs s while $what at $modeText '
          '(preset ${_openPreset?.name})');
      setState(() {
        _dropHint = 'Dropped after $secs s at $modeText. Try a lower preset, '
            'a plain OTG adapter, or a powered hub.';
      });
      unawaited(_close());
    }
    unawaited(_refresh());
  }

  Future<List<_UsbInfo>> _listUsb() async {
    final raw = await _channel.invokeListMethod<Object?>('usbDevices');
    return [
      for (final m in raw ?? const [])
        _UsbInfo.fromMap(m! as Map<Object?, Object?>),
    ];
  }

  Future<void> _refresh() async {
    try {
      final supported = await UvcCamera.isSupported();
      final usb = await _listUsb();
      final granted =
          await _channel.invokeMethod<bool>('cameraPermissionGranted');
      if (!mounted) return;
      setState(() {
        _supported = supported;
        _usb = usb;
        _cameraGranted = granted;
      });
      _note('supported=$supported, ${usb.where((u) => u.isVideo).length} '
          'camera(s), ${usb.where((u) => !u.isVideo).length} other USB '
          'device(s)');
    } catch (e, st) {
      _noteError('list failed', e, st);
    }
  }

  /// The plugin's own handle for [cam]: by path first, else by vendor:product
  /// (the path changes on replug).
  Future<UvcCameraDevice?> _pluginDevice(_UsbInfo cam) async {
    final all = await UvcCamera.getDevices();
    for (final d in all.values) {
      if (d.name == cam.deviceName) return d;
    }
    for (final d in all.values) {
      if (d.vendorId == cam.vendorId && d.productId == cam.productId) return d;
    }
    return null;
  }

  Future<bool> _hasUsbPermission(String deviceName) async =>
      await _channel.invokeMethod<bool>(
        'usbHasPermission',
        {'deviceName': deviceName},
      ) ??
      false;

  /// CAMERA first (Android 9+ denies USB video access without it), then USB.
  Future<void> _requestAccess(_UsbInfo cam) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final camera =
          await _channel.invokeMethod<bool>('requestCameraPermission') ?? false;
      _note('CAMERA: ${camera ? 'granted' : 'denied'}');
      if (!camera) {
        _note('USB permission will most likely be denied without CAMERA');
      }
      final before = await _hasUsbPermission(cam.deviceName);
      _note('USB hasPermission before: $before');
      if (before) return;
      final dev = await _pluginDevice(cam);
      if (dev == null) {
        _note('plugin does not list ${cam.key}; tap refresh');
        return;
      }
      final watch = Stopwatch()..start();
      bool? ok;
      try {
        ok = await UvcCamera.requestDevicePermission(dev);
      } catch (e, st) {
        _noteError('USB permission request', e, st);
      }
      watch.stop();
      final after = await _hasUsbPermission(cam.deviceName);
      final fast = watch.elapsedMilliseconds < 300;
      _note('USB permission: plugin=${ok ?? 'error'}, hasPermission after: '
          '$after, answer in ${watch.elapsedMilliseconds} ms'
          '${fast && !after ? ' (< 300 ms, so no dialog was shown)' : ''}');
      if (!after) {
        _note('no USB permission. Use the replug "Always" route below.');
      }
    } catch (e, st) {
      _noteError('permission step failed', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
      unawaited(_refresh());
    }
  }

  /// `UvcCameraController.initialize()` catches its own failure and hands it to
  /// an unawaited future, so it returns normally and the error surfaces later
  /// as an uncaught zone error (and from `dispose()`). Capture it here.
  Future<({bool ok, Object? error, StackTrace? stack})> _initialize(
    UvcCameraController c,
  ) async {
    Object? error;
    StackTrace? stack;
    await runZonedGuarded(() async {
      try {
        await c.initialize();
      } catch (e, st) {
        error = e;
        stack = st;
      }
      // Give a swallowed error one event-loop turn to reach the zone handler.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }, (e, st) {
      error ??= e;
      stack ??= st;
    });
    final ok = error == null && c.value.isInitialized;
    return (ok: ok, error: error, stack: stack);
  }

  /// Opens [cam] at exactly [preset]. No fallback to other presets: the test
  /// matrix needs to know what each preset does on its own.
  Future<void> _openCamera(_UsbInfo cam, UvcCameraResolutionPreset preset) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _dropHint = null;
    });
    try {
      await _close();
      if (!await _hasUsbPermission(cam.deviceName)) {
        _note('Permission needed first');
        return;
      }
      final dev = await _pluginDevice(cam);
      if (dev == null) {
        _note('plugin does not list ${cam.key}; tap refresh');
        return;
      }
      _lastCam = cam;
      _lastPreset = preset;
      _note('opening preset ${preset.name} (asks for ${_presetAsk[preset]})');
      final c = UvcCameraController(device: dev, resolutionPreset: preset);
      final r = await _initialize(c);
      if (!r.ok) {
        _noteError(
          'initialize(${preset.name}) failed',
          r.error ?? 'initialize returned but the controller is not ready',
          r.stack,
        );
        await _safeDispose(c);
        return;
      }
      if (!mounted) {
        await _safeDispose(c);
        return;
      }
      _camSubs
        ..add(c.cameraErrorEvents.listen(
          (e) => _note('ERROR event: ${e.error.type.name} '
              '${e.error.toMap()}'),
          onError: (Object e) => _note('error stream: $e'),
        ))
        ..add(c.cameraStatusEvents.listen(
          (e) => _note('status: ${e.payload.toMap()}'),
          onError: (Object e) => _note('status stream: $e'),
        ));
      final m = c.value.previewMode;
      _note('preview mode used (${preset.name}): ${m?.frameWidth}x'
          '${m?.frameHeight} ${m?.frameFormat.name}, texture id '
          '${c.textureId}');
      _openWatch
        ..reset()
        ..start();
      setState(() {
        _controller = c;
        _openKey = cam.key;
        _openPreset = preset;
        _ready = true;
      });
      unawaited(_readModes(c));
    } catch (e, st) {
      _noteError('open failed', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The plugin has no public "supported sizes" call on the controller, but
  /// the platform interface has one. Lab only: imported from `src/`.
  Future<void> _readModes(UvcCameraController c) async {
    try {
      final modes = await UvcCameraPlatformInterface.instance
          .getSupportedModes(c.cameraId);
      if (!mounted || _controller != c) return;
      setState(() => _modes = modes);
      _note('camera offers ${modes.length} mode(s): '
          '${modes.map(_modeText).join(', ')}');
    } catch (e, st) {
      _noteError('supported modes unreadable', e, st);
    }
  }

  String _modeText(UvcCameraMode m) =>
      '${m.frameWidth}x${m.frameHeight} ${m.frameFormat.name}';

  /// Disposes [c]. A failed `initialize()` rethrows its original error here,
  /// so it is logged as the real cause.
  Future<void> _safeDispose(UvcCameraController c) async {
    try {
      await c.dispose();
    } catch (e, st) {
      _noteError('dispose reported', e, st);
    }
  }

  Future<void> _close() async {
    _ticker?.cancel();
    _ticker = null;
    for (final s in _camSubs) {
      unawaited(s.cancel());
    }
    _camSubs.clear();
    final c = _controller;
    _controller = null;
    _ready = false;
    _openKey = null;
    _remaining = 0;
    _recording = false;
    _modes = const [];
    _openWatch.stop();
    if (mounted) setState(() {});
    if (c != null) await _safeDispose(c);
  }

  /// Records [seconds] seconds, copies the clip to `inspection/`, and for a
  /// quick clip plays it back on the page. The playback is the decisive test:
  /// a clip that plays while the live preview is blank means frames arrive but
  /// the preview texture is not drawn.
  Future<void> _record(int seconds, {required bool play}) async {
    final c = _controller;
    if (c == null || !_ready || _busy || c.value.isRecordingVideo) return;
    final mode = c.value.previewMode;
    if (mode == null) {
      _note('no preview mode to record with');
      return;
    }
    setState(() {
      _busy = true;
      _recording = true;
      _result = null;
      _remaining = seconds;
    });
    await _clip?.dispose();
    _clip = null;
    final started = DateTime.now();
    try {
      await c.startVideoRecording(mode);
      _note('recording started (${mode.frameWidth}x${mode.frameHeight}, '
          '$seconds s)');
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _remaining = seconds - t.tick);
      });
      await Future<void>.delayed(Duration(seconds: seconds));
      _ticker?.cancel();
      _ticker = null;
      if (_controller != c) throw StateError('camera closed while recording');
      final file = await c.stopVideoRecording();
      final wall = DateTime.now().difference(started);
      final size = await File(file.path).length();
      final dir = await InspectionUploader.directory();
      final name =
          'usbdirect_${play ? 'quick' : 'rec'}_${mode.frameWidth}x${mode.frameHeight}_'
          '${mode.frameFormat.name}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final copy = await File(file.path).copy('${dir.path}/$name');
      final text = 'file: ${file.path}\n'
          'size: ${(size / 1024).toStringAsFixed(0)} KB'
          '${size < 20 * 1024 ? '  (tiny: probably no frames)' : ''}\n'
          'duration (wall clock, start to stop): ${wall.inMilliseconds} ms\n'
          'copied to: ${copy.path}\n'
          'check resolution and fps with: ffprobe <file>';
      _note('recording saved, $size bytes');
      if (mounted) setState(() => _result = text);
      if (play && mounted) await _startClip(copy);
    } catch (e, st) {
      _noteError('record failed', e, st);
      _ticker?.cancel();
      _ticker = null;
      if (c.value.isRecordingVideo) {
        try {
          await c.stopVideoRecording();
        } catch (e2, st2) {
          _noteError('stop after failure', e2, st2);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _recording = false;
          _remaining = 0;
        });
      }
    }
  }

  Future<void> _startClip(File f) async {
    final vc = VideoPlayerController.file(f);
    try {
      await vc.initialize();
      await vc.setLooping(true);
      await vc.play();
      _note('clip playback: ${vc.value.size.width.toInt()}x'
          '${vc.value.size.height.toInt()}, '
          '${vc.value.duration.inMilliseconds} ms');
      if (!mounted) {
        await vc.dispose();
        return;
      }
      setState(() => _clip = vc);
    } catch (e, st) {
      _noteError('clip playback failed', e, st);
      await vc.dispose();
    }
  }

  Future<void> _showNativeLog() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('nativeLog');
      final lines = [for (final l in (r?['lines'] as List?) ?? const []) '$l'];
      if (!mounted) return;
      setState(() {
        _nativeLog = 'logcat exit ${r?['exit']}, ${r?['total']} lines total, '
            '${lines.length} matched\n${lines.join('\n')}';
      });
    } catch (e, st) {
      _noteError('native log failed', e, st);
    }
  }

  Future<void> _clearNativeLog() async {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('clearNativeLog');
      final exit = r?['exit'];
      _note(exit == 0
          ? 'native log cleared'
          : 'logcat -c refused (exit $exit: ${r?['output']}). Log not cleared; '
              'read it from $stamp onwards.');
    } catch (e, st) {
      _noteError('clear native log failed', e, st);
    }
    if (mounted) setState(() => _nativeLog = null);
  }

  Widget _deviceText(_UsbInfo d, ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d.name}  ${d.key}', style: theme.textTheme.titleSmall),
          Text('${d.deviceName}\ninterfaces: ${d.interfaces.join('  ')}\n'
              'max power: ${d.maxPowerMa >= 0 ? '${d.maxPowerMa} mA' : '?'}'
              ' · app has USB permission: ${d.hasPermission}'),
        ],
      );

  String get _impellerText => !_impellerKnown
      ? '…'
      : _impeller == null
          ? 'on (default, not set)'
          : _impeller!
              ? 'on'
              : 'OFF (labImpeller=false)';

  Widget _presetButtons(_UsbInfo d, ThemeData theme) {
    final enabled = !_busy && d.hasPermission;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Open at preset', style: theme.textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: [
            for (final p in UvcCameraResolutionPreset.values)
              FilledButton.tonal(
                onPressed: enabled ? () => _openCamera(d, p) : null,
                child: Text(p.name),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            for (final p in UvcCameraResolutionPreset.values)
              '${p.name}: asks ${_presetAsk[p]}',
            'Closest-area fix applied (vendored uvccamera, see '
                'third_party/uvccamera/PATCHES.md). The mode actually used is '
                'shown after open.',
          ].join('\n'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _previewArea(UvcCameraController c, ThemeData theme) {
    final m = c.value.previewMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mode: ${m == null ? '?' : _modeText(m)}'
          '${m == null ? '' : '  aspect ${m.aspectRatio.toStringAsFixed(3)}'}'
          ' · preset ${_openPreset?.name} · texture id ${c.textureId}',
        ),
        const SizedBox(height: 4),
        // Purple backing behind the texture: purple = the texture draws
        // nothing (no frames, or frames not composited); white = widget is
        // not laid out at all; video = fine.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: _MeasuredBox(
              builder: (_) => Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF6A1B9A)),
                  ),
                  UvcCameraPreview(c),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _controller;
    final cameras = _usb.where((u) => u.isVideo).toList();
    final others = _usb.where((u) => !u.isVideo).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB camera direct (test)'),
        actions: [
          IconButton(
            tooltip: 'Refresh devices',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Lab test only. Plugin supported: ${_supported ?? '…'} · '
            'CAMERA permission: ${_cameraGranted ?? '…'} · '
            '${cameras.length} camera(s) · Impeller: $_impellerText',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (cameras.isEmpty)
            const ListTile(title: Text('No USB camera found')),
          for (final d in cameras)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _deviceText(d, theme),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _requestAccess(d),
                      child: const Text('Request permissions'),
                    ),
                    if (!d.hasPermission)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Permission needed first'),
                      ),
                    const SizedBox(height: 8),
                    _presetButtons(d, theme),
                  ],
                ),
              ),
            ),
          if (others.isNotEmpty)
            ExpansionTile(
              title: Text('Other USB devices (not cameras): ${others.length}'),
              children: [
                for (final d in others)
                  ListTile(
                    title: Text('${d.name}  ${d.key}'),
                    subtitle: Text('interfaces: ${d.interfaces.join('  ')}'),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          const Text(
            'No permission dialog? Unplug and replug the webcam. When Android '
            'asks "Open movement_capture_lab when this device is connected?", '
            'tick "Always" and tap OK.',
          ),
          if (_dropHint != null) ...[
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_dropHint!),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy || _lastCam == null || _lastPreset == null
                          ? null
                          : () => _openCamera(_lastCam!, _lastPreset!),
                      child: Text('Reopen (${_lastPreset?.name})'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_ready && c != null) ...[
            const SizedBox(height: 12),
            _previewArea(c, theme),
            const SizedBox(height: 8),
            if (_modes.isNotEmpty)
              Text(
                'Camera offers (${_modes.length}):\n'
                '${_modes.map(_modeText).join('\n')}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy || _recording
                      ? null
                      : () => _record(_quickSeconds, play: true),
                  icon: const Icon(Icons.movie),
                  label: Text(_recording && _remaining > 0 && _clip == null
                      ? 'Recording… $_remaining s'
                      : 'Quick clip $_quickSeconds s'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _recording
                      ? null
                      : () => _record(_recordSeconds, play: false),
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Record $_recordSeconds s'),
                ),
                OutlinedButton(
                  onPressed: _recording ? null : _close,
                  child: const Text('Close camera'),
                ),
              ],
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            SelectableText(_result!),
          ],
          if (_clip != null && _clip!.value.isInitialized) ...[
            const SizedBox(height: 8),
            Text('Quick clip playback', style: theme.textTheme.labelLarge),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: AspectRatio(
                  aspectRatio: _clip!.value.aspectRatio,
                  child: VideoPlayer(_clip!),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'If it still fails\n'
                '• Try the webcam through a plain USB-C to USB-A OTG adapter, '
                'not the hub. The hub\'s Ethernet chip shares the bus, and many '
                'phones cannot power a webcam through an unpowered hub.\n'
                '• Try a powered hub.\n'
                '• Check "max power" above; a power-hungry webcam is a hint.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Native log (this app only)', style: theme.textTheme.titleMedium),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _showNativeLog,
                child: const Text('Native log'),
              ),
              OutlinedButton(
                onPressed: _nativeLog == null
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: _nativeLog!),
                        );
                        _note('native log copied');
                      },
                child: const Text('Copy'),
              ),
              OutlinedButton(
                onPressed: _clearNativeLog,
                child: const Text('Clear log'),
              ),
            ],
          ),
          if (_nativeLog != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _nativeLog!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Events and errors', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (_log.isEmpty) const Text('None yet'),
          for (final line in _log.take(60))
            SelectableText(line, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Wraps [builder]'s output and shows the size it was laid out at, so a
/// zero-size or unbounded preview (H3) is visible on screen.
class _MeasuredBox extends StatefulWidget {
  const _MeasuredBox({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_MeasuredBox> createState() => _MeasuredBoxState();
}

class _MeasuredBoxState extends State<_MeasuredBox> {
  final _key = GlobalKey();
  Size? _size;

  void _measure() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final size = box != null && box.hasSize ? box.size : null;
    if (size != _size && mounted) setState(() => _size = size);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final s = _size;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(key: _key, child: widget.builder(context)),
        Text(
          s == null
              ? 'preview widget size: not laid out'
              : 'preview widget size: ${s.width.toStringAsFixed(0)} x '
                  '${s.height.toStringAsFixed(0)}'
                  '${s.isEmpty ? '  (EMPTY: layout bug)' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
