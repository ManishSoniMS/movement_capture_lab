import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/capture_step.dart';
import '../domain/capture_storage.dart';
import '../domain/uploader.dart';

enum UploadStatus { queued, uploading, done, failed }

class _Job {
  _Job(this.clip);
  final MovementClip clip;
  UploadStatus status = UploadStatus.queued;
  double progress = 0;
  String? analysisId;
  UploadCancellation cancellation = UploadCancellation();
}

/// Uploads recorded steps one at a time, in the background, so the camera is
/// never blocked while the next step is filmed.
///
/// Files of a step are deleted as soon as that step uploaded. A failed step
/// keeps its files until [retryFailed] succeeds or the session is torn down.
class StepUploads {
  StepUploads({
    required MovementUploader uploader,
    required CaptureStorage storage,
    required VoidCallback onChanged,
  })  : _uploader = uploader,
        _storage = storage,
        _onChanged = onChanged;

  final MovementUploader _uploader;
  final CaptureStorage _storage;
  final VoidCallback _onChanged;
  final Map<CaptureStep, _Job> _jobs = {};
  Future<void> _tail = Future<void>.value();
  bool _cancelled = false;

  bool get isEmpty => _jobs.isEmpty;

  bool get hasPending => _jobs.values.any((j) =>
      j.status == UploadStatus.queued || j.status == UploadStatus.uploading);

  /// True while any queued step is not yet uploaded (queued, running or
  /// failed). Quitting now would lose it.
  bool get hasUnfinished => _jobs.values.any((j) => j.status != UploadStatus.done);

  int get failedCount =>
      _jobs.values.where((j) => j.status == UploadStatus.failed).length;

  /// Mean progress over every queued step, 0–1. 1 when nothing was queued.
  double get progress => _jobs.isEmpty
      ? 1
      : _jobs.values.map((j) => j.progress).reduce((a, b) => a + b) /
          _jobs.length;

  String? analysisIdFor(CaptureStep step) => _jobs[step]?.analysisId;

  void enqueue(MovementClip clip) {
    final job = _Job(clip);
    _jobs[clip.step] = job;
    _schedule(job);
    _onChanged();
  }

  /// Re-queues every failed step.
  void retryFailed() {
    for (final job in _jobs.values) {
      if (job.status != UploadStatus.failed) continue;
      job
        ..status = UploadStatus.queued
        ..progress = 0
        ..cancellation = UploadCancellation();
      _schedule(job);
    }
    _onChanged();
  }

  /// Stops running and queued uploads. Late results are ignored.
  void cancelAll() {
    _cancelled = true;
    for (final job in _jobs.values) {
      job.cancellation.cancel();
    }
  }

  /// Removes the files of every step that is not already uploaded.
  Future<void> deleteAllFiles() async {
    for (final job in _jobs.values) {
      if (job.status != UploadStatus.done) await _deleteFiles(job);
    }
  }

  void _schedule(_Job job) {
    _tail = _tail.then((_) => _run(job)).catchError((Object e, StackTrace s) {
      debugPrint('movement_capture: upload job failed: $e\n$s');
    });
  }

  Future<void> _run(_Job job) async {
    if (_cancelled || job.cancellation.isCancelled) return;
    job
      ..status = UploadStatus.uploading
      ..progress = 0;
    _onChanged();
    final cancellation = job.cancellation;
    try {
      final id = await _uploader.upload(
        job.clip,
        onProgress: (p) {
          if (cancellation.isCancelled) return;
          job.progress = p < 0 ? 0 : (p > 1 ? 1 : p);
          _onChanged();
        },
        cancellation: cancellation,
      );
      if (cancellation.isCancelled) return;
      if (id.isEmpty) throw StateError('Uploader returned an empty id');
      job
        ..analysisId = id
        ..status = UploadStatus.done
        ..progress = 1;
      await _deleteFiles(job);
    } catch (e) {
      if (cancellation.isCancelled) return;
      debugPrint('movement_capture: upload of ${job.clip.step.name} failed $e');
      job.status = UploadStatus.failed;
    }
    _onChanged();
  }

  Future<void> _deleteFiles(_Job job) async {
    await _storage.deletePath(job.clip.file.path);
    final landmarks = job.clip.landmarksFile;
    if (landmarks != null) await _storage.deletePath(landmarks.path);
  }
}
