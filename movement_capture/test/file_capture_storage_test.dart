import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/data/file_capture_storage.dart';
import 'package:movement_capture/src/domain/capture_storage.dart';

void main() {
  late Directory root;
  late CaptureStorage storage;
  late Directory pluginVideos;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mc_storage_test');
    pluginVideos = Directory('${root.path}/plugin/camera/videos')
      ..createSync(recursive: true);
    storage = FileCaptureStorage(
      cacheDir: () async => root,
      pluginVideosDir: () async => pluginVideos,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('adopt moves the file into movement_capture/', () async {
    final raw = File('${root.path}/raw.mp4')..writeAsStringSync('x');
    final adopted = await storage.adopt(raw.path);
    expect(adopted.parent.path, '${root.path}/movement_capture');
    expect(adopted.existsSync(), isTrue);
    expect(raw.existsSync(), isFalse);
  });

  test('purgeAll removes our folder and stray mp4 in the cache root', () async {
    final raw = File('${root.path}/raw.mp4')..writeAsStringSync('x');
    await storage.adopt(raw.path);
    final stray = File('${root.path}/stray.mp4')..writeAsStringSync('z');
    final keep = File('${root.path}/keep.txt')..writeAsStringSync('k');
    await storage.purgeAll();
    expect(Directory('${root.path}/movement_capture').existsSync(), isFalse);
    expect(stray.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
  });

  test('deletePath ignores a missing file', () async {
    await storage.deletePath('${root.path}/missing.mp4');
  });

  test('purgeAll removes mp4 files left in the plugin recording folder',
      () async {
    final stray = File('${pluginVideos.path}/REC_1.mp4')
      ..writeAsStringSync('x');
    final keep = File('${pluginVideos.path}/note.txt')..writeAsStringSync('k');
    await storage.purgeAll();
    expect(stray.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
  });

  test('purgeAll copes with a missing plugin recording folder', () async {
    await pluginVideos.delete(recursive: true);
    await storage.purgeAll();
  });
}
