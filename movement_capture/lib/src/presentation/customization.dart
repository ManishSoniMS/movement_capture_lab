import 'package:flutter/material.dart';

import '../domain/camera_choice.dart';
import '../domain/capture_issue.dart';
import '../domain/capture_state.dart';

/// Every user-facing string. English defaults; the host passes translations.
/// Templates use {elapsed}, {total}, {percent} and {n} placeholders.
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
        'Recording keeps stopping. Please check the position and the light, then tap Try again.',
    this.uploadingTemplate = 'Sending video… {percent}%',
    this.uploadFailed = 'Could not send the video. Tap Retry.',
    this.completed = 'Video sent for analysis.',
    this.cameraNone = 'No camera found. Check the USB cable, then tap Retry.',
    this.cameraPermissionDenied =
        'Camera access is off. Allow camera access for this app in Settings, then tap Retry.',
    this.cameraStreamUnsupported =
        'This camera cannot check the video while recording. Choose another camera.',
    this.cameraOther =
        'The camera stopped working. Check the USB cable, then tap Retry.',
    this.startRecording = 'Start recording',
    this.cancel = 'Cancel',
    this.tryAgain = 'Try again',
    this.retry = 'Retry',
    this.done = 'Done',
    this.cameraExternalSingle = 'USB camera',
    this.cameraExternalTemplate = 'USB camera {n}',
    this.cameraFrontSingle = 'Tablet front camera',
    this.cameraFrontTemplate = 'Tablet front camera {n}',
    this.cameraBackSingle = 'Tablet back camera',
    this.cameraBackTemplate = 'Tablet back camera {n}',
    this.chooseCamera = 'Choose camera',
    this.usbCamerasHeading = 'USB cameras',
    this.tabletCamerasHeading = 'Tablet cameras',
    this.noUsbCameraNotice = 'No USB camera found. Using the tablet camera.',
    this.refreshCameras = 'Refresh list',
    this.useAnotherCamera = 'Use another camera',
    this.noLiveChecksNotice =
        'This device cannot check the video while recording. Please stay inside the box until recording ends.',
    this.openSettings = 'Open Settings',
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
  final String cameraNone;
  final String cameraPermissionDenied;
  final String cameraStreamUnsupported;
  final String cameraOther;
  final String startRecording;
  final String cancel;
  final String tryAgain;
  final String retry;
  final String done;
  final String cameraExternalSingle;
  final String cameraExternalTemplate;
  final String cameraFrontSingle;
  final String cameraFrontTemplate;
  final String cameraBackSingle;
  final String cameraBackTemplate;
  final String chooseCamera;
  final String usbCamerasHeading;
  final String tabletCamerasHeading;
  final String noUsbCameraNotice;
  final String refreshCameras;
  final String useAnotherCamera;
  final String noLiveChecksNotice;
  final String openSettings;

  String issue(CaptureIssue i) => switch (i) {
        CaptureIssue.multiplePeople => issueMultiplePeople,
        CaptureIssue.noPerson => issueNoPerson,
        CaptureIssue.outOfFrame => issueOutOfFrame,
        CaptureIssue.tooDark => issueTooDark,
        CaptureIssue.tooBright => issueTooBright,
        CaptureIssue.backlit => issueBacklit,
      };

  String cameraFailure(CameraFailure f) => switch (f) {
        CameraFailure.noCamera => cameraNone,
        CameraFailure.permissionDenied => cameraPermissionDenied,
        CameraFailure.streamUnsupported => cameraStreamUnsupported,
        CameraFailure.other => cameraOther,
      };

  String cameraLabel(CameraChoice c) {
    final (single, template) = switch (c.kind) {
      CameraKind.external => (cameraExternalSingle, cameraExternalTemplate),
      CameraKind.front => (cameraFrontSingle, cameraFrontTemplate),
      CameraKind.back => (cameraBackSingle, cameraBackTemplate),
    };
    return c.countOfKind > 1
        ? template.replaceAll('{n}', '${c.ordinal}')
        : single;
  }

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
    this.switchCamera = Icons.cameraswitch_outlined,
    this.usbCamera = Icons.usb,
    this.tabletCamera = Icons.tablet_android,
    this.selectedCamera = Icons.check_circle,
    this.refresh = Icons.refresh,
    this.info = Icons.info_outline,
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
  final IconData switchCamera;
  final IconData usbCamera;
  final IconData tabletCamera;
  final IconData selectedCamera;
  final IconData refresh;
  final IconData info;

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
