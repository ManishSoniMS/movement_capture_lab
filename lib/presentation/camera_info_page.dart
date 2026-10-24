import 'dart:io' show Platform;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movement_capture/movement_capture.dart';

/// Compares what the Flutter camera plugin sees with what Android itself
/// offers, and states the likely cause when the USB camera is missing.
class CameraInfoPage extends StatefulWidget {
  const CameraInfoPage({super.key});

  @override
  State<CameraInfoPage> createState() => _CameraInfoPageState();
}

class _Report {
  const _Report({
    required this.implementation,
    required this.plugin,
    required this.camera2,
    required this.usb,
    required this.externalFeature,
    this.error,
  });

  final String implementation;
  final List<CameraDescription> plugin;
  final List<Map<String, Object?>> camera2;
  final List<Map<String, Object?>> usb;
  final bool externalFeature;
  final String? error;

  String get verdict {
    final pluginExternal =
        plugin.where((c) => c.lensDirection == CameraLensDirection.external);
    final androidExternal =
        camera2.where((c) => c['facing'] == 'external').toList();

    if (pluginExternal.isNotEmpty) {
      return 'OK: the app can see the USB camera '
          '(id ${pluginExternal.map((c) => c.name).join(', ')}).';
    }
    if (Platform.isIOS) {
      return 'No USB camera listed. On iOS, USB cameras work only on iPads '
          'with USB-C running iPadOS 17 or later, and only when the app uses '
          'the patched camera_avfoundation (dependency_overrides in '
          'pubspec.yaml). iPhones never list USB cameras. The built-in '
          'cameras above will be used.';
    }
    if (androidExternal.isNotEmpty) {
      final numeric = androidExternal.where((c) => c['numericId'] == true);
      if (numeric.isEmpty) {
        return 'Android offers the USB camera with id '
            '"${androidExternal.first['id']}", which is not a plain number. '
            'The Camera2 plugin skips such ids. Report this; it needs a small '
            'plugin fork.';
      }
      if (!implementation.contains('AndroidCamera') ||
          implementation.contains('CameraX')) {
        return 'Android offers the USB camera (id ${numeric.first['id']}), but '
            'the app is using $implementation. camera_android must be a direct '
            'dependency of this app (pubspec.yaml), then rebuild.';
      }
      return 'Android offers the USB camera (id ${numeric.first['id']}), but '
          'the plugin did not list it. Unplug and replug the webcam, then tap '
          'Refresh.';
    }
    if (usb.isNotEmpty) {
      return 'The tablet sees a USB video device, but Android does not offer it '
          'to apps as a camera. Unplug and replug it, then Refresh. If it stays '
          'like this, apps cannot use it through the camera system and the USB '
          'camera library path (Path B) is needed.';
    }
    return 'No USB camera found. Check the cable, the USB-C adapter or hub, '
        'and that the webcam has power.';
  }
}

class _CameraInfoPageState extends State<CameraInfoPage> {
  static const _channel = MethodChannel('lab/camera_diagnostics');
  late Future<_Report> _report = _load();

  Future<_Report> _load() async {
    final implementation = CameraPlatform.instance.runtimeType.toString();
    var plugin = <CameraDescription>[];
    var camera2 = <Map<String, Object?>>[];
    var usb = <Map<String, Object?>>[];
    var feature = false;
    final errors = <String>[];

    try {
      plugin = await MovementCapture.listCameras();
    } catch (e) {
      errors.add('plugin: $e');
    }
    // The native diagnostics channel exists only on Android.
    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeListMethod<Object?>('camera2Cameras');
        camera2 = [
          for (final m in raw ?? const [])
            Map<String, Object?>.from(m! as Map<Object?, Object?>),
        ];
      } catch (e) {
        errors.add('camera2: $e');
      }
      try {
        final raw = await _channel.invokeListMethod<Object?>('usbVideoDevices');
        usb = [
          for (final m in raw ?? const [])
            Map<String, Object?>.from(m! as Map<Object?, Object?>),
        ];
      } catch (e) {
        errors.add('usb: $e');
      }
      try {
        feature =
            await _channel.invokeMethod<bool>('hasExternalCameraFeature') ??
                false;
      } catch (e) {
        errors.add('feature: $e');
      }
    }

    return _Report(
      implementation: implementation,
      plugin: plugin,
      camera2: camera2,
      usb: usb,
      externalFeature: feature,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  String _asText(_Report r) {
    final b = StringBuffer()
      ..writeln('Verdict: ${r.verdict}')
      ..writeln('Active plugin: ${r.implementation}')
      ..writeln('Device declares camera.external: ${r.externalFeature}')
      ..writeln('Flutter plugin cameras:');
    for (final c in r.plugin) {
      b.writeln(
          '  id ${c.name} · ${c.lensDirection.name} · ${c.sensorOrientation}°');
    }
    b.writeln('Android Camera2 cameras:');
    for (final c in r.camera2) {
      b.writeln(
          '  id ${c['id']} · ${c['facing']} · numericId=${c['numericId']} '
          '· backwardCompatible=${c['backwardCompatible']} '
          '· level=${c['hardwareLevel']} · ${c['sensorOrientation']}°');
    }
    b.writeln('USB video devices:');
    for (final d in r.usb) {
      b.writeln(
          '  ${d['name']} · vendor ${d['vendorId']} · product ${d['productId']}');
    }
    if (r.error != null) b.writeln('Errors:\n${r.error}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _report = _load()),
          ),
        ],
      ),
      body: FutureBuilder<_Report>(
        future: _report,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(r.verdict, style: theme.textTheme.titleMedium),
                ),
              ),
              ListTile(
                title: const Text('Active camera plugin'),
                subtitle: Text(r.implementation),
              ),
              ListTile(
                title: const Text('Device declares external camera support'),
                subtitle: Text('${r.externalFeature}'),
              ),
              const _Heading('What the Flutter plugin sees'),
              if (r.plugin.isEmpty) const ListTile(title: Text('None')),
              for (final c in r.plugin)
                ListTile(
                  leading: Icon(c.lensDirection == CameraLensDirection.external
                      ? Icons.usb
                      : Icons.tablet_android),
                  title: Text('id ${c.name} · ${c.lensDirection.name}'),
                  subtitle: Text('sensor ${c.sensorOrientation}°'),
                ),
              const _Heading('What Android (Camera2) offers'),
              if (r.camera2.isEmpty) const ListTile(title: Text('None')),
              for (final c in r.camera2)
                ListTile(
                  leading: Icon(c['facing'] == 'external'
                      ? Icons.usb
                      : Icons.tablet_android),
                  title: Text('id ${c['id']} · ${c['facing']}'),
                  subtitle: Text('numeric id: ${c['numericId']} · '
                      'backward compatible: ${c['backwardCompatible']} · '
                      'level: ${c['hardwareLevel']} · '
                      'sensor ${c['sensorOrientation']}°'),
                ),
              const _Heading('USB video devices'),
              if (r.usb.isEmpty) const ListTile(title: Text('None')),
              for (final d in r.usb)
                ListTile(
                  leading: const Icon(Icons.cable),
                  title: Text('${d['name']}'),
                  subtitle: Text(
                      'vendor ${d['vendorId']} · product ${d['productId']}'),
                ),
              if (r.error != null) ...[
                const _Heading('Errors'),
                Text(r.error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _asText(r)));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Report copied')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy report'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
