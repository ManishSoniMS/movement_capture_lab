import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../data/plugin_camera_gateway.dart';
import '../data/usb_direct_camera_gateway.dart';
import '../domain/camera_gateway.dart';

/// Shows [gateway]'s live picture: `CameraPreview` for the plugin, or a
/// `Texture` with the reported aspect ratio for direct USB. [child] is drawn
/// on top, scaled with the picture, in both cases.
class CameraPreviewHost extends StatelessWidget {
  const CameraPreviewHost({super.key, required this.gateway, this.child});

  final CameraGateway gateway;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final g = gateway;
    if (g is PluginCameraGateway) {
      return CameraPreview(g.controller, child: child);
    }
    if (g is UsbDirectCameraGateway) {
      final id = g.textureId;
      if (id == null) return const SizedBox.shrink();
      return AspectRatio(
        aspectRatio: g.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Texture(textureId: id),
            if (child != null) child!,
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
