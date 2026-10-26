# movement_capture

Operator-assisted full-body video capture for kiosk tablets. The operator taps
**Start recording**; the package checks the picture live (one person, whole
body in view, lighting OK), counts down, records up to 30 s, uploads through
a host-supplied uploader and returns an analysis id.

## Host-agnostic rules

The package must NOT:

1. import Dio, Riverpod, GoRouter or any host code. The host passes a `MovementUploader`.
2. contain user text the host cannot replace. The host passes `MovementCaptureStrings` (English defaults built in).
3. hardcode colours or icons. It inherits the host `Theme`; pass `MovementCaptureStyle` / `MovementCaptureIcons` to override.
4. persist anything. It only uses `<cache>/movement_capture/` and exposes `MovementCapture.purgeAll()`.
5. decide consent, login or navigation. `open` returns a `MovementCaptureResult`; the host decides what happens next.

## Install

```yaml
dependencies:
  movement_capture:
    git:
      url: <private repo URL>
      path: packages/movement_capture
      ref: movement_capture-v0.1.0
```

Host apps must also add `camera_android` to their own pubspec.yaml; otherwise
Android falls back to CameraX, which may not list USB cameras.

**iOS:** add `NSCameraUsageDescription` to `Info.plist` and set the iOS
deployment target to 15.5. For USB webcams on iPad, the host app must also
override `camera_avfoundation` with the patched copy in
`third_party/camera_avfoundation` (see `PATCHES.md`), using
`dependency_overrides` in the host's own `pubspec.yaml`. Without the override,
iPads use only their built-in cameras.

Requirements: `minSdkVersion` >= 24. The host must grant CAMERA (via MDM on
kiosks). No microphone permission is needed. The host must check video
consent **before** calling `open`.

## Use

```dart
final report = await MovementCapture.checkSupport(); // never throws
if (report.canRun) {
  final result = await MovementCapture.open(
    context,
    config: MovementCaptureConfig(metadata: {'chatSessionId': id}),
    uploader: MyUploader(),
  );
  // result.status: completed | cancelled | unsupported
  // result.analysisId: first analysis id, or null
}
```

`open` runs the same check itself and returns `unsupported` without opening
the camera on a blocking problem. Blocking problems: wrong platform, old OS,
camera permission not declared (Android manifest / iOS `NSCameraUsageDescription`),
restricted camera access, no camera, ML Kit unavailable (for example Apple
Silicon simulators). Fixable: denied camera access (the screen offers **Open
Settings**), low storage. The capture screen keeps the display awake and
restores the previous setting on close.

Call `MovementCapture.purgeAll()` on logout and before login (never while a
capture screen is open).

## Camera choice

First USB camera if connected; otherwise the tablet front camera (with a
notice), otherwise the back camera. The operator can switch from the bottom
bar before Start, on the "Recording keeps stopping" panel and on the "camera
unavailable" panel. `open(onCameraChanged:)` fires only when the operator picks
a camera, never on automatic fallback; keep `camera.name` in memory and pass it
back as `preferredCameraId`. The package stores nothing.

## MovementUploader contract

```dart
Future<String> upload(MovementClip clip,
    {required void Function(double progress) onProgress,
     required UploadCancellation cancellation});
```

Return a non-empty analysis id; throw on failure (the package shows Retry).
Retry policy (attempts, backoff) is the uploader's job. Stop when
`cancellation` fires. The package deletes the clip file after success.

`MovementClip` also carries `platform` (`android`/`ios`), `cameraKind`
(`external`/`front`/`back`), `fileMirrored` (true only for the iOS front
camera) and `liveChecks` (false when the recording ran without quality
checks). `clip.deviceFields` gives them as multipart strings.

## MovementCaptureConfig fields (defaults)

| Field                                                          | Default                                                                      |
|----------------------------------------------------------------|------------------------------------------------------------------------------|
| maxDuration                                                    | 30 s (clamped 5-30 s)                                                        |
| countdown                                                      | 3 s                                                                          |
| stableBeforeStart                                              | 1500 ms                                                                      |
| violationGrace                                                 | 400 ms                                                                       |
| maxRestarts                                                    | 3                                                                            |
| resolution                                                     | ResolutionPreset.high                                                        |
| preferredCameraId                                              | null                                                                         |
| cameraRotationDegrees                                          | 0 (USB camera only; tablet cameras derive it)                                |
| mirrorExternalPreview / mirrorFrontPreview / mirrorBackPreview | null (platform default: USB on; front on for Android, off for iOS; back off) |
| orientation                                                    | auto (tablets landscape, phones portrait)                                    |
| allowRecordingWithoutLiveChecks                                | true                                                                         |
| safeZoneInset                                                  | 0.075                                                                        |
| minLandmarkLikelihood                                          | 0.5                                                                          |
| minMeanLuma / maxMeanLuma                                      | 60 / 200                                                                     |
| maxClippedFraction                                             | 0.25                                                                         |
| minCenterToBorderLuma                                          | 0.6                                                                          |
| analysisInterval                                               | 150 ms                                                                       |
| metadata                                                       | {}                                                                           |
| restoreOrientations                                            | [] (system default)                                                          |
