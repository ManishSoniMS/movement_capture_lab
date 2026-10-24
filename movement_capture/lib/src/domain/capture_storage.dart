import 'dart:io';

/// The only way capture files are created, moved or deleted.
abstract interface class CaptureStorage {
  /// Moves the plugin's output at [rawPath] into the package folder so
  /// [purgeAll] always finds it.
  Future<File> adopt(String rawPath);

  /// Deletes [path] if it exists. Never throws on a missing or locked file.
  Future<void> deletePath(String path);

  /// Deletes the package folder and any stray .mp4 in the cache root
  /// (crash/kill mid-recording). NEVER call while recording.
  Future<void> purgeAll();
}
