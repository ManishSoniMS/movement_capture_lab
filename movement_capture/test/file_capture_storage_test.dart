import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/data/file_capture_storage.dart';
import 'package:movement_capture/src/domain/capture_storage.dart';

void main() {
  late Directory root;
  late CaptureStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mc_storage_test');
    storage = FileCaptureStorage(cacheDir: () async => root);
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
}
