import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uvccamera/uvccamera.dart';

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

/// LAB ONLY, TEMPORARY (kiosk-08 Part A): go/no-go test for talking to a USB
/// webcam directly over UVC, without Android's camera system.
///
/// Lists real cameras (video-class interface) apart from other USB devices,
/// asks for CAMERA and then USB permission, previews, records 10 s and copies
/// the clip to the `inspection/` folder for `adb pull`. Every error and plugin
/// event is shown on screen instead of crashing. Removed in Part B.
class UsbDirectTestPage extends StatefulWidget {
  const UsbDirectTestPage({super.key});

  @override
  State<UsbDirectTestPage> createState() => _UsbDirectTestPageState();
}

class _UsbDirectTestPageState extends State<UsbDirectTestPage> {
  static const _channel = MethodChannel('lab/camera_diagnostics');
  static const _recordSeconds = 10;

  /// Tried in order; the first that streams wins. `medium` is ~720p.
  static const _presets = [
    UvcCameraResolutionPreset.medium,
    UvcCameraResolutionPreset.low,
    UvcCameraResolutionPreset.min,
  ];

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
  bool? _supported;
  bool _busy = false;
  int _remaining = 0;
  Timer? _ticker;
  String? _result;

  @override
  void initState() {
    super.initState();
    _subs.add(UvcCamera.deviceEventStream.listen(
      (e) {
        _note('device event: ${e.type.name} ${e.device.name}');
        if (e.type == UvcCameraDeviceEventType.detached ||
            e.type == UvcCameraDeviceEventType.disconnected) {
          final open = _openKey;
          final match = _usb.where((u) => u.deviceName == e.device.name);
          if (open != null && match.any((u) => u.key == open)) {
            _note('open camera was unplugged');
            unawaited(_close());
          }
        }
        unawaited(_refresh());
      },
      onError: (Object e) => _note('device stream error: $e'),
    ));
    unawaited(_refresh());
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

  Future<void> _openCamera(_UsbInfo cam) async {
    if (_busy) return;
    setState(() => _busy = true);
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
      for (final preset in _presets) {
        _note('trying preset ${preset.name}');
        final c = UvcCameraController(device: dev, resolutionPreset: preset);
        final r = await _initialize(c);
        if (!r.ok) {
          _noteError(
            'initialize(${preset.name}) failed',
            r.error ?? 'initialize returned but the controller is not ready',
            r.stack,
          );
          await _safeDispose(c);
          continue;
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
            '${m?.frameHeight} ${m?.frameFormat.name}');
        setState(() {
          _controller = c;
          _openKey = cam.key;
          _ready = true;
        });
        return;
      }
      _note('all presets failed. See "If it still fails" below.');
    } catch (e, st) {
      _noteError('open failed', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    if (mounted) setState(() {});
    if (c != null) await _safeDispose(c);
  }

  Future<void> _record() async {
    final c = _controller;
    if (c == null || !_ready || _busy || c.value.isRecordingVideo) return;
    final mode = c.value.previewMode;
    if (mode == null) {
      _note('no preview mode to record with');
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _remaining = _recordSeconds;
    });
    final started = DateTime.now();
    try {
      await c.startVideoRecording(mode);
      _note('recording started (${mode.frameWidth}x${mode.frameHeight})');
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _remaining = _recordSeconds - t.tick);
      });
      await Future<void>.delayed(const Duration(seconds: _recordSeconds));
      _ticker?.cancel();
      _ticker = null;
      if (_controller != c) throw StateError('camera closed while recording');
      final file = await c.stopVideoRecording();
      final wall = DateTime.now().difference(started);
      final size = await File(file.path).length();
      final dir = await InspectionUploader.directory();
      final name =
          'usbdirect_${mode.frameWidth}x${mode.frameHeight}_${mode.frameFormat.name}'
          '_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(file.path).copy('${dir.path}/$name');
      final text = 'file: ${file.path}\n'
          'size: ${(size / 1024).toStringAsFixed(0)} KB\n'
          'duration (wall clock, start to stop): ${wall.inMilliseconds} ms\n'
          'copied to: ${dir.path}/$name\n'
          'check resolution and fps with: ffprobe <file>';
      _note('recording saved, $size bytes');
      if (mounted) setState(() => _result = text);
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
          _remaining = 0;
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _controller;
    final recording = _ready && (c?.value.isRecordingVideo ?? false);
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
            '${cameras.length} camera(s)',
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
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy ? null : () => _requestAccess(d),
                          child: const Text('Request permissions'),
                        ),
                        FilledButton(
                          onPressed: _busy || !d.hasPermission
                              ? null
                              : () => _openCamera(d),
                          child: Text(_openKey == d.key
                              ? 'Reopen preview'
                              : 'Open preview'),
                        ),
                      ],
                    ),
                    if (!d.hasPermission)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Permission needed first'),
                      ),
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
          if (_ready && c != null) ...[
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: UvcCameraPreview(c),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy || recording ? null : _record,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: Text(recording
                      ? 'Recording… $_remaining s'
                      : 'Record $_recordSeconds s'),
                ),
                OutlinedButton(
                  onPressed: recording ? null : _close,
                  child: const Text('Close camera'),
                ),
              ],
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            SelectableText(_result!),
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
