import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/usb_direct.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../data/uploaders.dart';

/// LAB: hardware check for the package's direct-USB backend (the same code
/// path `MovementCapture.open` uses when Camera2 does not list the webcam).
///
/// Lists video-class USB devices, asks for CAMERA then USB permission, opens
/// the camera at a preset, shows the live texture, records a quick clip,
/// plays it back and copies it to `inspection/` for `adb pull`. The Native
/// log button shows this app's logcat lines for the USB stack.
class UsbDirectTestPage extends StatefulWidget {
  const UsbDirectTestPage({super.key});

  @override
  State<UsbDirectTestPage> createState() => _UsbDirectTestPageState();
}

class _UsbDirectTestPageState extends State<UsbDirectTestPage> {
  static const _channel = MethodChannel('lab/camera_diagnostics');
  static const _presets = <ResolutionPreset>[
    ResolutionPreset.low,
    ResolutionPreset.medium,
    ResolutionPreset.high,
    ResolutionPreset.veryHigh,
  ];

  final _log = <String>[];
  List<UsbVideoDevice> _devices = const [];
  UsbDirectCameraGateway? _gateway;
  StreamSubscription<CameraLost>? _lostSub;
  bool _busy = false;
  bool _recording = false;
  String? _result;
  String? _nativeLog;
  VideoPlayerController? _clip;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    unawaited(_close());
    unawaited(_clip?.dispose());
    super.dispose();
  }

  void _note(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    debugPrint('usb-direct: $line');
    if (mounted) setState(() => _log.add('$t $line'));
  }

  Future<void> _refresh() async {
    final list = await MovementCapture.listUsbVideoDevices();
    if (!mounted) return;
    setState(() => _devices = list);
    _note('${list.length} USB video device(s)');
  }

  Future<void> _requestAccess(UsbVideoDevice d) async {
    final r = await MovementCapture.requestUsbPermission(d.deviceName);
    _note('permission: ${r.name}');
    await _refresh();
  }

  Future<void> _open(UsbVideoDevice d, ResolutionPreset preset) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _close();
    final target = usbTargetSize(preset);
    _note('opening ${preset.name} (asks for $target)');
    final g = UsbDirectCameraGateway(
      deviceName: d.deviceName,
      vendorId: d.vendorId,
      productId: d.productId,
      config: MovementCaptureConfig(resolution: preset),
      analysisInterval: const Duration(milliseconds: 200),
      newRecordingPath: () async {
        final dir = await getTemporaryDirectory();
        return '${dir.path}/usb_test_${DateTime.now().millisecondsSinceEpoch}.mp4';
      },
    );
    try {
      await g.initialize();
      _gateway = g;
      _lostSub = g.lost.listen((l) {
        _note('LOST: $l');
        unawaited(_close());
      });
      _note('mode used: ${g.frameSize} ${g.format}, texture ${g.textureId}');
      _note('camera offers ${g.supportedModes.length} mode(s): '
          '${g.supportedModes.join(', ')}');
    } catch (e) {
      _note('open failed: $e');
      await g.dispose();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    await _lostSub?.cancel();
    _lostSub = null;
    final g = _gateway;
    _gateway = null;
    await g?.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _quickClip(int seconds) async {
    final g = _gateway;
    if (g == null || _busy) return;
    setState(() {
      _busy = true;
      _recording = true;
      _result = null;
    });
    try {
      await g.startRecording();
      _note('recording started (${g.frameSize}, $seconds s)');
      await Future<void>.delayed(Duration(seconds: seconds));
      final path = await g.stopRecording();
      final size = await File(path).length();
      final dir = await InspectionUploader.directory();
      final copy = await File(path).copy(
          '${dir.path}/usbdirect_${g.frameSize}_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await File(path).delete();
      _note('recording saved, $size bytes');
      if (mounted) {
        setState(() => _result = 'copied to: ${copy.path}\n'
            'size: ${(size / 1024).toStringAsFixed(0)} KB'
            '${size < 20 * 1024 ? ' (tiny: probably no frames)' : ''}\n'
            'check with: ffprobe <file>');
      }
      await _play(copy);
    } catch (e) {
      _note('record failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _recording = false;
        });
      }
    }
  }

  Future<void> _play(File f) async {
    await _clip?.dispose();
    final vc = VideoPlayerController.file(f);
    try {
      await vc.initialize();
      await vc.setLooping(true);
      await vc.play();
      _note('clip playback: ${vc.value.size.width.toInt()}x'
          '${vc.value.size.height.toInt()}, ${vc.value.duration.inMilliseconds} ms');
      if (mounted) setState(() => _clip = vc);
    } catch (e) {
      _note('clip playback failed: $e');
      await vc.dispose();
    }
  }

  Future<void> _showNativeLog() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('nativeLog');
      final lines = [for (final l in (r?['lines'] as List?) ?? const []) '$l'];
      if (mounted) {
        setState(() => _nativeLog = 'logcat exit ${r?['exit']}, '
            '${r?['total']} lines total, ${lines.length} matched\n'
            '${lines.join('\n')}');
      }
    } catch (e) {
      _note('native log failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = _gateway;
    return Scaffold(
      appBar: AppBar(title: const Text('USB camera (direct)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Video devices', style: theme.textTheme.titleMedium),
          if (_devices.isEmpty)
            const ListTile(title: Text('None (or native library missing)')),
          for (final d in _devices)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.productName, style: theme.textTheme.titleSmall),
                    Text('${d.deviceName} · '
                        '${d.vendorId.toRadixString(16)}:'
                        '${d.productId.toRadixString(16)} · '
                        '${d.maxPowerMa ?? '?'} mA · '
                        'permission: ${d.hasPermission ? 'yes' : 'no'}'),
                    const SizedBox(height: 8),
                    if (!d.hasPermission)
                      FilledButton(
                        onPressed: () => _requestAccess(d),
                        child: const Text('Allow access'),
                      )
                    else
                      Wrap(spacing: 8, children: [
                        for (final p in _presets)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _open(d, p),
                            child: Text(p.name),
                          ),
                      ]),
                  ],
                ),
              ),
            ),
          Row(children: [
            TextButton(onPressed: _refresh, child: const Text('Refresh')),
            if (g != null) ...[
              TextButton(onPressed: _close, child: const Text('Close')),
              FilledButton(
                onPressed: _busy ? null : () => _quickClip(3),
                child: Text(_recording ? 'Recording…' : 'Quick clip (3 s)'),
              ),
            ],
          ]),
          if (g != null && g.textureId != null)
            AspectRatio(
              aspectRatio: g.aspectRatio,
              child: ColoredBox(
                color: Colors.purple, // shows through if frames are not drawn
                child: Texture(textureId: g.textureId!),
              ),
            ),
          if (_clip != null && _clip!.value.isInitialized)
            AspectRatio(
              aspectRatio: _clip!.value.aspectRatio,
              child: VideoPlayer(_clip!),
            ),
          if (_result != null) SelectableText(_result!),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton(
                onPressed: _showNativeLog, child: const Text('Native log')),
          ]),
          if (_nativeLog != null)
            SelectableText(_nativeLog!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          const SizedBox(height: 8),
          Text('Log', style: theme.textTheme.titleMedium),
          SelectableText(_log.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }
}
