import 'package:flutter/material.dart';

import '../domain/camera_choice.dart';
import '../domain/capture_issue.dart';
import '../domain/capture_state.dart';
import '../domain/capture_step.dart';
import '../domain/config.dart';

/// Every user-facing string. English defaults; the host passes translations.
/// Templates use {elapsed}, {total}, {percent}, {n} and {step} placeholders.
class MovementCaptureStrings {
  const MovementCaptureStrings({
    this.issueMultiplePeople =
        'Only one person should be in view. Others, please step aside.',
    this.issueNoPerson = 'No one in view. Please stand inside the box.',
    this.issueNoFace = 'No face in view. Please look at the camera.',
    this.issueOutOfFrame =
        'Not fully in view. Please move to the centre of the box.',
    this.issueFaceTooFar = 'Please come closer to the camera.',
    this.issueTooDark = 'Too dark. Please turn on more light.',
    this.issueTooBright =
        'Too much light. Please reduce the light or move away from the window.',
    this.issueBacklit =
        'Bright light is behind the patient. Please close the curtain or turn the light off.',
    this.interrupted =
        'Recording stopped. It will start again when this is fixed.',
    this.hintArmed = 'Waiting for the patient to be in position…',
    this.getReady = 'Get ready',
    this.recordingTemplate = 'Recording {elapsed} of {total} seconds',
    this.starting = 'Starting camera…',
    this.needsOperator =
        'Recording keeps stopping. Please check the position and the light, then tap Try again.',
    this.uploadingTemplate = 'Sending videos… {percent}%',
    this.uploadFailed = 'Some videos could not be sent. Tap Retry.',
    this.completed = 'All videos sent for analysis.',
    this.cameraNone = 'No camera found. Check the USB cable, then tap Retry.',
    this.cameraPermissionDenied =
        'Camera access is off. Allow camera access for this app in Settings, then tap Retry.',
    this.cameraStreamUnsupported =
        'This camera cannot check the video while recording. Choose another camera.',
    this.cameraOther =
        'The camera stopped working. Check the USB cable, then tap Retry.',
    this.startRecording = 'Start',
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
    this.stepTitleFullBody = 'Full body',
    this.stepTitleFace = 'Face',
    this.stepTitleHands = 'Hands',
    this.stepTitleFeet = 'Feet',
    this.stepInstructionFullBody =
        'Ask the patient to stand inside the box, then tap Start.',
    this.stepInstructionFace =
        'Ask the patient to come close and look straight at the camera, then tap Start.',
    this.stepInstructionHands =
        'Ask the patient to hold both hands up to the camera, palms facing it and fingers spread, then tap Start.',
    this.stepInstructionFeet =
        'Point the camera at the patient\'s feet so both feet are inside the box, then tap Start.',
    this.stepProgressTemplate = 'Step {n} of {total} · {step}',
    this.stepSavedTemplate = 'Saved: {step}',
    this.skipStep = 'Skip this step',
    this.selfStepInstructionFullBody =
        'Stand the phone up so the screen faces you. Tap Start, then step back until your whole body is inside the box.',
    this.selfStepInstructionFace =
        'Hold the phone at arm\'s length and look straight at it. Tap Start.',
    this.selfStepInstructionHands =
        'Stand the phone up. Tap Start, then hold both hands in front of it, palms facing the screen and fingers spread.',
    this.selfStepInstructionFeet =
        'Lean the phone against something low, facing your feet. Tap Start, then place both feet inside the box.',
    this.selfHintArmed =
        'Get into position. Recording starts when you are inside the box.',
    this.selfNeedsOperator =
        'Recording keeps stopping. Check the light and your position, then tap Try again.',
    this.selfIssueBacklit =
        'Bright light is behind you. Please close the curtain or turn around.',
    this.voiceStartingInTemplate = 'Starting in {n}',
    this.voiceRecording = 'Recording. Please stay still.',
    this.voiceGood = 'Good. Stay there.',
    this.voiceStepDone = 'Done.',
    this.voiceFinishing = 'Sending the videos. Please wait.',
    this.mute = 'Mute voice',
    this.unmute = 'Turn voice on',
  });

  final String issueMultiplePeople;
  final String issueNoPerson;
  final String issueNoFace;
  final String issueOutOfFrame;
  final String issueFaceTooFar;
  final String issueTooDark;
  final String issueTooBright;
  final String issueBacklit;
  final String interrupted;
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
  final String stepTitleFullBody;
  final String stepTitleFace;
  final String stepTitleHands;
  final String stepTitleFeet;
  final String stepInstructionFullBody;
  final String stepInstructionFace;
  final String stepInstructionHands;
  final String stepInstructionFeet;
  final String stepProgressTemplate;
  final String stepSavedTemplate;
  final String skipStep;
  final String selfStepInstructionFullBody;
  final String selfStepInstructionFace;
  final String selfStepInstructionHands;
  final String selfStepInstructionFeet;
  final String selfHintArmed;
  final String selfNeedsOperator;
  final String selfIssueBacklit;
  final String voiceStartingInTemplate;
  final String voiceRecording;
  final String voiceGood;
  final String voiceStepDone;
  final String voiceFinishing;
  final String mute;
  final String unmute;

  String issue(CaptureIssue i) => switch (i) {
        CaptureIssue.multiplePeople => issueMultiplePeople,
        CaptureIssue.noPerson => issueNoPerson,
        CaptureIssue.noFace => issueNoFace,
        CaptureIssue.outOfFrame => issueOutOfFrame,
        CaptureIssue.faceTooFar => issueFaceTooFar,
        CaptureIssue.tooDark => issueTooDark,
        CaptureIssue.tooBright => issueTooBright,
        CaptureIssue.backlit => issueBacklit,
      };

  String stepInstructionFor(CaptureStep s, CaptureMode mode) =>
      mode == CaptureMode.assisted
          ? stepInstruction(s)
          : switch (s) {
              CaptureStep.fullBody => selfStepInstructionFullBody,
              CaptureStep.face => selfStepInstructionFace,
              CaptureStep.hands => selfStepInstructionHands,
              CaptureStep.feet => selfStepInstructionFeet,
            };

  String hintArmedFor(CaptureMode mode) =>
      mode == CaptureMode.assisted ? hintArmed : selfHintArmed;

  String needsOperatorFor(CaptureMode mode) =>
      mode == CaptureMode.assisted ? needsOperator : selfNeedsOperator;

  String issueFor(CaptureIssue i, CaptureMode mode) =>
      mode == CaptureMode.selfGuided && i == CaptureIssue.backlit
          ? selfIssueBacklit
          : issue(i);

  String voiceStartingIn(int n) =>
      voiceStartingInTemplate.replaceAll('{n}', '$n');

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

  String stepTitle(CaptureStep s) => switch (s) {
        CaptureStep.fullBody => stepTitleFullBody,
        CaptureStep.face => stepTitleFace,
        CaptureStep.hands => stepTitleHands,
        CaptureStep.feet => stepTitleFeet,
      };

  String stepInstruction(CaptureStep s) => switch (s) {
        CaptureStep.fullBody => stepInstructionFullBody,
        CaptureStep.face => stepInstructionFace,
        CaptureStep.hands => stepInstructionHands,
        CaptureStep.feet => stepInstructionFeet,
      };

  /// [index] is 0-based.
  String stepProgress(int index, int total, CaptureStep s) =>
      stepProgressTemplate
          .replaceAll('{n}', '${index + 1}')
          .replaceAll('{total}', '$total')
          .replaceAll('{step}', stepTitle(s));

  String stepSaved(CaptureStep s) =>
      stepSavedTemplate.replaceAll('{step}', stepTitle(s));

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
    this.noFace = Icons.face_retouching_off,
    this.outOfFrame = Icons.crop_free,
    this.faceTooFar = Icons.zoom_in,
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
    this.stepFullBody = Icons.accessibility_new,
    this.stepFace = Icons.face,
    this.stepHands = Icons.back_hand_outlined,
    this.stepFeet = Icons.directions_walk,
    this.skipStep = Icons.skip_next,
    this.saved = Icons.check,
    this.voiceOn = Icons.volume_up,
    this.voiceOff = Icons.volume_off,
  });

  final IconData multiplePeople;
  final IconData noPerson;
  final IconData noFace;
  final IconData outOfFrame;
  final IconData faceTooFar;
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
  final IconData stepFullBody;
  final IconData stepFace;
  final IconData stepHands;
  final IconData stepFeet;
  final IconData skipStep;
  final IconData saved;
  final IconData voiceOn;
  final IconData voiceOff;

  IconData issue(CaptureIssue i) => switch (i) {
        CaptureIssue.multiplePeople => multiplePeople,
        CaptureIssue.noPerson => noPerson,
        CaptureIssue.noFace => noFace,
        CaptureIssue.outOfFrame => outOfFrame,
        CaptureIssue.faceTooFar => faceTooFar,
        CaptureIssue.tooDark => tooDark,
        CaptureIssue.tooBright => tooBright,
        CaptureIssue.backlit => backlit,
      };

  IconData step(CaptureStep s) => switch (s) {
        CaptureStep.fullBody => stepFullBody,
        CaptureStep.face => stepFace,
        CaptureStep.hands => stepHands,
        CaptureStep.feet => stepFeet,
      };
}

/// Optional colour overrides. Null = taken from the host theme
/// (colorScheme.error / colorScheme.primary).
class MovementCaptureStyle {
  const MovementCaptureStyle({
    this.errorColor,
    this.activeColor,
    this.skeletonBodyColor,
    this.skeletonFaceColor,
    this.skeletonHandColor,
    this.skeletonFootColor,
  });

  /// Default: colorScheme.error.
  final Color? errorColor;

  /// Default: colorScheme.primary.
  final Color? activeColor;

  /// Defaults: primary, tertiary, secondary, inversePrimary.
  final Color? skeletonBodyColor;
  final Color? skeletonFaceColor;
  final Color? skeletonHandColor;
  final Color? skeletonFootColor;
}
