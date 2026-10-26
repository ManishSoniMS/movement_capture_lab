import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:path_provider/path_provider.dart';

/// Simulates a 2 s upload. With [fail], always throws (tests the Retry UI).
class MockUploader implements MovementUploader {
  MockUploader({this.fail = false});
  final bool fail;

  @override
  Future<String> upload(
    MovementClip clip, {
    required void Function(double progress) onProgress,
    required UploadCancellation cancellation,
  }) async {
    for (var i = 1; i <= 10; i++) {
      if (cancellation.isCancelled) throw StateError('cancelled');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      onProgress(i / 10);
    }
    if (fail) throw Exception('Simulated upload failure');
    return 'mock-${clip.step.name}-${clip.capturedAtUtc.millisecondsSinceEpoch}';
  }
}

/// LAB ONLY. Copies each clip to the app's external files folder so it can be
/// pulled with adb and inspected (check V4). Never use outside the lab.
class InspectionUploader implements MovementUploader {
  static Future<Directory> directory() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/inspection');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<int> clear() async {
    final dir = await directory();
    var count = 0;
    await for (final e in dir.list()) {
      if (e is File) {
        await e.delete();
        count++;
      }
    }
    return count;
  }

  @override
  Future<String> upload(
    MovementClip clip, {
    required void Function(double progress) onProgress,
    required UploadCancellation cancellation,
  }) async {
    final dir = await directory();
    final base = 'session_${clip.sessionId.substring(0, 8)}'
        '_${clip.stepIndex + 1}-${clip.step.name}'
        '_${clip.platform}_${clip.cameraKind}'
        '_mirrored-${clip.fileMirrored}_checks-${clip.liveChecks}'
        '_${clip.duration.inMilliseconds}ms'
        '_r${clip.retakes}';
    onProgress(0.3);
    await clip.file.copy('${dir.path}/$base.mp4');
    if (clip.landmarksFile != null) {
      await clip.landmarksFile!.copy('${dir.path}/$base.landmarks.json');
    }
    if (cancellation.isCancelled) throw StateError('cancelled');
    onProgress(1);
    return 'inspection:$base';
  }
}

/// Real HTTP upload following the backend contract. The kiosk app's own
/// uploader is built the same way, but on its shared Dio client.
///
/// Contract (one request per step):
///   POST <endpointUrl>  multipart/form-data
///   files:  video (video/mp4), landmarks (application/json, optional)
///   fields: durationMs, resolutionPreset, capturedAt (ISO-8601 UTC),
///           platform, cameraKind, fileMirrored, liveChecks,
///           sessionId, step, stepIndex, stepCount, + every metadata entry
///   200/201 → {"analysisId": "mv_01JB7Q2K9X4T3R8N5C6D"}
class HttpUploader implements MovementUploader {
  HttpUploader({required this.endpointUrl, this.bearerToken});

  final String endpointUrl;
  final String? bearerToken;
  final Dio _dio = Dio();

  static const int _maxAttempts = 3;

  @override
  Future<String> upload(
    MovementClip clip, {
    required void Function(double progress) onProgress,
    required UploadCancellation cancellation,
  }) async {
    final token = CancelToken();
    unawaited(cancellation.whenCancelled.then((_) => token.cancel()));

    for (var attempt = 1;; attempt++) {
      try {
        final form = FormData.fromMap({
          'video': await MultipartFile.fromFile(
            clip.file.path,
            filename: 'movement.mp4',
            contentType: DioMediaType.parse('video/mp4'),
          ),
          if (clip.landmarksFile != null)
            'landmarks': await MultipartFile.fromFile(
              clip.landmarksFile!.path,
              filename: 'landmarks.json',
              contentType: DioMediaType.parse('application/json'),
            ),
          ...clip.formFields,
        });

        final response = await _dio.post<Map<String, dynamic>>(
          endpointUrl,
          data: form,
          cancelToken: token,
          options: Options(
            sendTimeout: const Duration(minutes: 2),
            receiveTimeout: const Duration(seconds: 60),
            headers: {
              if (bearerToken != null && bearerToken!.isNotEmpty)
                'Authorization': 'Bearer $bearerToken',
            },
          ),
          onSendProgress: (sent, total) {
            if (total > 0) onProgress(sent / total);
          },
        );

        final id = response.data?['analysisId'];
        if (id is! String || id.isEmpty) {
          throw StateError('Response is missing analysisId');
        }
        return id;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        if (!_isRetryable(e) || attempt >= _maxAttempts) rethrow;
        onProgress(0);
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  bool _isRetryable(DioException e) => switch (e.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          true,
        DioExceptionType.badResponse => (e.response?.statusCode ?? 0) >= 500,
        _ => false,
      };
}
