import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/capture_storage.dart';

/// Stores captures under `<cache>/movement_capture/`.
class FileCaptureStorage implements CaptureStorage {
  /// [cacheDir] defaults to the platform temporary directory; tests override it.
  const FileCaptureStorage({
    Future<Directory> Function() cacheDir = getTemporaryDirectory,
    Future<Directory> Function() pluginVideosDir = _iosPluginVideosDir,
  })  : _cacheDir = cacheDir,
        _pluginVideosDir = pluginVideosDir;

  final Future<Directory> Function() _cacheDir;
  final Future<Directory> Function() _pluginVideosDir;

  /// The iOS camera plugin records into `<app tmp>/camera/videos`, which is a
  /// different folder from path_provider's temporary directory on iOS.
  static Future<Directory> _iosPluginVideosDir() async =>
      Directory('${Directory.systemTemp.path}${Platform.pathSeparator}camera'
          '${Platform.pathSeparator}videos');

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
      await _deleteMp4sIn(tmp);
      await _deleteMp4sIn(await _pluginVideosDir());
    } on FileSystemException {
      // Best effort; the next call retries.
    }
  }

  Future<void> _deleteMp4sIn(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.mp4')) {
        await deletePath(entity.path);
      }
    }
  }
}
