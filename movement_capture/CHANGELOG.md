# Changelog

All notable changes to `movement_capture`. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow semantic versioning; before 1.0, a minor version may contain breaking changes, marked **BREAKING**.

## [Unreleased]

## [0.9.0] · 2026-10-26
### Added
- Review before upload: each recorded clip plays back with the tracked skeleton in sync; "Use this video", "Record again" or "Cancel" (`reviewBeforeUpload`, default on).
- Retake counting: `CaptureStepResult.retakes`, upload fields `retakes` and `reviewed`.
- Quit at any time: Cancel on every screen state including camera start-up and uploading; the back gesture always quits; a confirmation appears when unsent work would be lost.
- Dependency: `video_player`.
### Changed
- The camera is released during review and reopened afterwards.
- The back gesture now works while uploads run (it used to be ignored). Stopping cancels the uploads and deletes their files.

## [0.8.0] · 2026-10-26
### Added
- Hands step: MediaPipe Hand Landmarker (21 points per hand, up to 2 hands) on Android and iOS, with the hand skeleton on screen.
- Hands step checks: `noHands`, `oneHand` (when `requireBothHands`), and hands out of the box.
- `landmarks.json` for the hands step (`hands[]` with `handedness`, `side`, `score`, 21 points as `[x, y, z]`).
- Config `handTracking`, `requireBothHands`; support warning `handTrackingUnavailable`.
- `MODELS.md` listing bundled models.
### Changed
- iOS plugin now depends on `MediaPipeTasksVision` (static framework); the Swift Package Manager manifest was removed (the app builds with CocoaPods).
- Android plugin depends on `com.google.mediapipe:tasks-vision:0.10.26`.

## [0.7.1] · 2026-10-26
### Fixed
- Skeleton not aligned with the person: analysed frames are now rotated exactly as the preview is (iOS: frames are already upright; Android USB cameras: sensor/screen rule instead of a fixed 0°).
- Android front camera: left/right of the skeleton swapped; the preview was mirrored twice.
- Missing hand and leg points (caused by the rotation error and a too-strict drawing threshold).
- Skeleton lagging behind movement.
### Changed
- **BREAKING:** `cameraRotationDegrees` is now `int?` (null = automatic, the new default).
- **BREAKING:** `analysisInterval` is now `Duration?` (null = 66 ms, 150 ms on low-memory devices).
- `skeletonMinLikelihood` default 0.5 → 0.2; uncertain points are drawn more transparent.
- `mirrorFrontPreview` default is now off on Android too.
- The full-body face count runs on every 3rd analysis.

## [0.7.0] · 2026-10-26
### Added
- `CaptureMode.assisted` (B2B) and `CaptureMode.selfGuided` (B2C).
- Spoken prompts through a host-supplied `MovementCaptureVoice` (`open(voice: …)`): step instructions, problems (repeated every 6 s if unresolved), countdown, recording, done. Mute button on screen.
- Self-guided wording (`self…` strings), larger text, 5 s default countdown.
- Config: `mode`, `voiceInAssisted`, `voiceIssueRepeat`.
### Changed
- `MovementCaptureConfig.countdown` is now nullable (`null` = mode default).

## [0.6.0] · 2026-10-26
### Added
- Capture sessions with up to four steps: `fullBody`, `face`, `hands`, `feet` (`config.steps`, `stepDurations`, `skippableSteps`, `stepCameras`).
- Face step checks: one face, inside the box, close enough (`faceMinWidthFraction`).
- `landmarks.json` (format version 1) for the full-body and face steps, grouped into face / body / hands / feet.
- Background uploads, one per step, with retry from the final screen.
- Upload fields `sessionId`, `step`, `stepIndex`, `stepCount`, and an optional `landmarks` file (`MovementClip.formFields`, `MovementClip.landmarksFile`).
- "Skip this step" button.
### Changed
- **BREAKING:** `MovementClip` has new required fields; uploaders should send `clip.formFields`.
- **BREAKING:** strings `hintIdle` removed (replaced by `stepInstruction…`); upload texts now refer to several videos.
- **BREAKING:** package folder layout reorganised (`analysis/`, `camera/`, `presentation/`, …). Public imports via `movement_capture.dart` are unchanged.
- `purgeAll()` runs only at session start and end (not on failures or camera switches).

## [0.5.0] · 2026-10-26
### Added
- Skeleton overlay: all 33 body points joined by lines, coloured by region, gliding between samples, face boxes and contours. Shown independently of the debug overlay (`showSkeleton`, `skeletonMinLikelihood`).
- Skeleton colours in `MovementCaptureStyle`.
### Changed
- The debug overlay shows only numbers plus red rings on failing points (the dots-only layer was removed).

## [0.4.0] · 2026-10-26
### Added
- `MovementCapture.checkSupport()` → `SupportReport` (never throws, never prompts).
- `MovementCapture.openAppSettings()`; "Open Settings" on the camera-access panel; automatic retry when returning from Settings.
- The screen stays awake during capture.
- Native plugin code (Android/iOS).
### Changed
- **BREAKING:** `open()` returns `MovementCaptureResult` (never null) and refuses to open on blocking support issues.
- The package is now a Flutter plugin.

## [0.3.1] · 2026-10-24
### Fixed
- "A CameraController was used after being disposed" on the first launch's permission prompt: the camera is no longer released on `inactive`.
- Overlapping camera operations: all camera work now runs in one serial queue.
- Closing the screen during an upload no longer waits for the upload.

## [0.3.0] · 2026-10-24
### Added
- iOS support: BGRA frames, per-platform rotation, a patched `camera_avfoundation` for iPad USB webcams.
- Recording without live checks on devices that can't stream during recording (`allowRecordingWithoutLiveChecks`, upload field `liveChecks`).
- Upload fields `platform`, `cameraKind`, `fileMirrored`.
- Automatic orientation (phones portrait, tablets landscape) and narrow-screen layout.
### Fixed
- iOS crash when opening the camera without `NSCameraUsageDescription` (documented requirement).
- iOS leftover recordings: `purgeAll()` also cleans `tmp/camera/videos/`.
- Double-mirrored iOS front camera preview.

## [0.2.0] · 2026-10-24
### Added
- Camera picker (USB cameras / tablet cameras) with automatic fallback to the front camera.
- `onCameraChanged` and `preferredCameraId`.
### Changed
- Android camera implementation switched to `camera_android` (Camera2) so USB webcams are listed.
- `CameraFailure.notConnected` renamed `noCamera`.

## [0.1.0] · 2026-10-22
### Added
- First version: operator-assisted full-body capture (5–30 s, no audio), live checks (in frame, one person, lighting), automatic restart, upload through `MovementUploader`, deletion of all files.
