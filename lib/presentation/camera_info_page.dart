import 'package:flutter/material.dart';
import 'package:movement_capture/movement_capture.dart';

/// Check V1: does the tablet see the webcam as an external camera?
class CameraInfoPage extends StatelessWidget {
  const CameraInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cameras on this device')),
      body: FutureBuilder<List<CameraDescription>>(
        future: MovementCapture.listCameras(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final cams = snap.data!;
          if (cams.isEmpty) return const Center(child: Text('No cameras found'));
          return ListView(
            children: [
              for (final c in cams)
                ListTile(
                  leading: Icon(c.lensDirection == CameraLensDirection.external
                      ? Icons.usb
                      : Icons.camera_alt_outlined),
                  title: Text('id ${c.name} · ${c.lensDirection.name}'),
                  subtitle: Text('sensorOrientation ${c.sensorOrientation}°'),
                ),
            ],
          );
        },
      ),
    );
  }
}
