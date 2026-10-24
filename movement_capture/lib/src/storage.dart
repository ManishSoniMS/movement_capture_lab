import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

/// The only code that touches capture files on disk.
abstract final class MovementCaptureStorage {
  static const String _folder = 'movement_capture';

  static Future<Directory> _sessionDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}${Platform.pathSeparator}$_folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Moves the plugin's output into our folder so purgeAll always finds it.
  static Future<File> adopt(XFile raw) async {
    final dir = await _sessionDir();
    final target = '${dir.path}${Platform.pathSeparator}'
        'capture_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final source = File(raw.path);
    try {
      return await source.rename(target);
    } on FileSystemException {
      final copy = await source.copy(target);
      await deletePath(raw.path);
      return copy;
    }
  }

  static Future<void> deletePath(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Already gone or locked; purgeAll catches it later.
    }
  }

  /// Deletes our folder and any stray .mp4 in the cache root (crash/kill
  /// mid-recording). NEVER call while recording.
  static Future<void> purgeAll() async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}${Platform.pathSeparator}$_folder');
      if (await dir.exists()) await dir.delete(recursive: true);
      await for (final entity in tmp.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.mp4')) {
          await deletePath(entity.path);
        }
      }
    } on FileSystemException {
      // Best effort; the next call retries.
    }
  }
}
