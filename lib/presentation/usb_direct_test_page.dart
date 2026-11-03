import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uvccamera/uvccamera.dart';

import '../data/uploaders.dart';

/// LAB ONLY, TEMPORARY (kiosk-08 Part A): go/no-go test for talking to a USB
/// webcam directly over UVC, without Android's camera system.
///
/// Lists UVC devices, asks for USB permission, previews, records 10 s and
/// copies the clip to the `inspection/` folder for `adb pull`. Every error and
/// plugin event is shown on screen instead of crashing. Removed in Part B.
class UsbDirectTestPage extends StatefulWidget {
  const UsbDirectTestPage({super.key});

  @override
  State<UsbDirectTestPage> createState() => _UsbDirectTestPageState();
}

class _UsbDirectTestPageState extends State<UsbDirectTestPage> {
  static const _recordSeconds = 10;

  final _log = <String>[];
  final _subs = <StreamSubscription<Object?>>[];
  final _camSubs = <StreamSubscription<Object?>>[];

  Map<String, UvcCameraDevice> _devices = {};
  UvcCameraController? _controller;
  UvcCameraDevice? _open;
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
          if (e.device.name == _open?.name) {
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
    if (c != null) unawaited(_safeDispose(c));
    super.dispose();
  }

  void _note(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    if (!mounted) return;
    setState(() => _log.insert(0, '$t  $line'));
  }

  Future<void> _refresh() async {
    try {
      final supported = await UvcCamera.isSupported();
      final devices = await UvcCamera.getDevices();
      if (!mounted) return;
      setState(() {
        _supported = supported;
        _devices = devices;
      });
      _note('supported=$supported, ${devices.length} UVC device(s)');
    } catch (e) {
      _note('list failed: $e');
    }
  }

  Future<void> _requestPermission(UvcCameraDevice d) async {
    try {
      final ok = await UvcCamera.requestDevicePermission(d);
      _note('permission for ${d.name}: ${ok ? 'granted' : 'denied'}');
    } catch (e) {
      _note('permission failed: $e');
    }
  }

  Future<void> _openCamera(UvcCameraDevice d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _close();
      // `medium` picks the mode with a frame area closest to 1280x720.
      final c = UvcCameraController(
        device: d,
        resolutionPreset: UvcCameraResolutionPreset.medium,
      );
      await c.initialize();
      if (!mounted) {
        await _safeDispose(c);
        return;
      }
      _camSubs
        ..add(c.cameraErrorEvents.listen(
          (e) {
            _note('ERROR event: ${e.error.type.name} ${e.error.toMap()}');
            if (_ticker != null) _note('error while recording');
          },
          onError: (Object e) => _note('error stream: $e'),
        ))
        ..add(c.cameraStatusEvents.listen(
          (e) => _note('status: ${e.payload.toMap()}'),
          onError: (Object e) => _note('status stream: $e'),
        ));
      final m = c.value.previewMode;
      _note('preview open: ${m?.frameWidth}x${m?.frameHeight} '
          '${m?.frameFormat.name}');
      setState(() {
        _controller = c;
        _open = d;
      });
    } catch (e) {
      _note('open failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _safeDispose(UvcCameraController c) async {
    try {
      await c.dispose();
    } catch (e) {
      _note('dispose failed: $e');
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
    _open = null;
    _remaining = 0;
    if (mounted) setState(() {});
    if (c != null) await _safeDispose(c);
  }

  Future<void> _record() async {
    final c = _controller;
    if (c == null || _busy || c.value.isRecordingVideo) return;
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
          'check fps with: ffprobe <file>';
      _note('recording saved, $size bytes');
      if (mounted) setState(() => _result = text);
    } catch (e) {
      _note('record failed: $e');
      _ticker?.cancel();
      _ticker = null;
      if (c.value.isRecordingVideo) {
        try {
          await c.stopVideoRecording();
        } catch (e2) {
          _note('stop after failure: $e2');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _controller;
    final recording = c?.value.isRecordingVideo ?? false;
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
            '${_devices.length} UVC device(s)',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            const ListTile(title: Text('No UVC device found')),
          for (final d in _devices.values)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: theme.textTheme.titleSmall),
                    Text('vendorId ${d.vendorId} · productId ${d.productId} · '
                        'class ${d.deviceClass}/${d.deviceSubclass}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _requestPermission(d),
                          child: const Text('Request permission'),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : () => _openCamera(d),
                          child: Text(_open?.name == d.name
                              ? 'Reopen preview'
                              : 'Open preview'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (c != null && c.value.isInitialized) ...[
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
