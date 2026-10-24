import 'package:flutter/material.dart';

import '../domain/capture_issue.dart';
import '../domain/capture_state.dart';

/// Every user-facing string. English defaults; the host passes translations.
/// Templates use {elapsed}, {total} and {percent} placeholders.
class MovementCaptureStrings {
  const MovementCaptureStrings({
    this.issueMultiplePeople =
        'Only one person should be in view. Others, please step aside.',
    this.issueNoPerson = 'No one in view. Please stand inside the box.',
    this.issueOutOfFrame =
        'Your whole body must be in view. Please step back or move to the centre.',
    this.issueTooDark = 'Too dark. Please turn on more light.',
    this.issueTooBright =
        'Too much light. Please reduce the light or move away from the window.',
    this.issueBacklit =
        'Bright light is behind the patient. Please close the curtain or turn the light off.',
    this.interrupted =
        'Recording stopped. It will start again when this is fixed.',
    this.hintIdle = 'Ask the patient to stand inside the box, then tap Start.',
    this.hintArmed = 'Waiting for the patient to be in position…',
    this.getReady = 'Get ready',
    this.recordingTemplate = 'Recording {elapsed} of {total} seconds',
    this.starting = 'Starting camera…',
    this.needsOperator =
        'Recording keeps stopping. Operator: please help the patient into position, then tap Try again.',
    this.uploadingTemplate = 'Sending video… {percent}%',
    this.uploadFailed = 'Could not send the video. Tap Retry.',
    this.completed = 'Video sent for analysis.',
    this.cameraNotConnected =
        'Webcam not found. Check the USB cable, then tap Retry.',
    this.cameraPermissionDenied =
        'Camera permission is off. Ask the administrator to allow camera access.',
    this.cameraStreamUnsupported =
        'This camera cannot check the video while recording. Contact support.',
    this.cameraOther =
        'The camera stopped working. Check the USB cable, then tap Retry.',
    this.startRecording = 'Start recording',
    this.cancel = 'Cancel',
    this.tryAgain = 'Try again',
    this.retry = 'Retry',
    this.done = 'Done',
  });

  final String issueMultiplePeople;
  final String issueNoPerson;
  final String issueOutOfFrame;
  final String issueTooDark;
  final String issueTooBright;
  final String issueBacklit;
  final String interrupted;
  final String hintIdle;
  final String hintArmed;
  final String getReady;
  final String recordingTemplate;
  final String starting;
  final String needsOperator;
  final String uploadingTemplate;
  final String uploadFailed;
  final String completed;
  final String cameraNotConnected;
  final String cameraPermissionDenied;
  final String cameraStreamUnsupported;
  final String cameraOther;
  final String startRecording;
  final String cancel;
  final String tryAgain;
  final String retry;
  final String done;

  String issue(CaptureIssue i) => switch (i) {
        CaptureIssue.multiplePeople => issueMultiplePeople,
        CaptureIssue.noPerson => issueNoPerson,
        CaptureIssue.outOfFrame => issueOutOfFrame,
        CaptureIssue.tooDark => issueTooDark,
        CaptureIssue.tooBright => issueTooBright,
        CaptureIssue.backlit => issueBacklit,
      };

  String cameraFailure(CameraFailure f) => switch (f) {
        CameraFailure.notConnected => cameraNotConnected,
        CameraFailure.permissionDenied => cameraPermissionDenied,
        CameraFailure.streamUnsupported => cameraStreamUnsupported,
        CameraFailure.other => cameraOther,
      };

  String recording(int elapsed, int total) => recordingTemplate
      .replaceAll('{elapsed}', '$elapsed')
      .replaceAll('{total}', '$total');

  String uploading(int percent) =>
      uploadingTemplate.replaceAll('{percent}', '$percent');
}

/// Icons. Hosts with a custom icon font pass their own glyphs.
class MovementCaptureIcons {
  const MovementCaptureIcons({
    this.multiplePeople = Icons.group_outlined,
    this.noPerson = Icons.person_off_outlined,
    this.outOfFrame = Icons.crop_free,
    this.tooDark = Icons.brightness_low,
    this.tooBright = Icons.wb_sunny_outlined,
    this.backlit = Icons.flare,
    this.cameraOff = Icons.videocam_off_outlined,
    this.uploadFailed = Icons.cloud_off_outlined,
    this.completed = Icons.check_circle_outline,
    this.recordingDot = Icons.fiber_manual_record,
    this.startRecording = Icons.videocam_outlined,
  });

  final IconData multiplePeople;
  final IconData noPerson;
  final IconData outOfFrame;
  final IconData tooDark;
  final IconData tooBright;
  final IconData backlit;
  final IconData cameraOff;
  final IconData uploadFailed;
  final IconData completed;
  final IconData recordingDot;
  final IconData startRecording;

  IconData issue(CaptureIssue i) => switch (i) {
        CaptureIssue.multiplePeople => multiplePeople,
        CaptureIssue.noPerson => noPerson,
        CaptureIssue.outOfFrame => outOfFrame,
        CaptureIssue.tooDark => tooDark,
        CaptureIssue.tooBright => tooBright,
        CaptureIssue.backlit => backlit,
      };
}

/// Optional colour overrides. Null = taken from the host theme
/// (colorScheme.error / colorScheme.primary).
class MovementCaptureStyle {
  const MovementCaptureStyle({this.errorColor, this.activeColor});
  final Color? errorColor;
  final Color? activeColor;
}
