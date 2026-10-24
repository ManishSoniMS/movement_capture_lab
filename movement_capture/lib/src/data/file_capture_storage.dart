import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/capture_storage.dart';

/// Stores captures under `<cache>/movement_capture/`.
class FileCaptureStorage implements CaptureStorage {
  /// [cacheDir] defaults to the platform temporary directory; tests override it.
  const FileCaptureStorage(
      {Future<Directory> Function() cacheDir = getTemporaryDirectory})
      : _cacheDir = cacheDir;

  final Future<Directory> Function() _cacheDir;

  static const String _folder = 'movement_capture';

  Future<Directory> _sessionDir() async {
    final tmp = await _cacheDir();
    final dir = Directory('${tmp.path}${Platform.pathSeparator}$_folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<File> adopt(String rawPath) async {
    final dir = await _sessionDir();
    final target = '${dir.path}${Platform.pathSeparator}'
        'capture_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final source = File(rawPath);
    try {
      return await source.rename(target);
    } on FileSystemException {
      final copy = await source.copy(target);
      await deletePath(rawPath);
      return copy;
    }
  }

  @override
  Future<void> deletePath(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Already gone or locked; purgeAll catches it later.
    }
  }

  @override
  Future<void> purgeAll() async {
    try {
      final tmp = await _cacheDir();
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
