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
  // result.steps: one entry per configured step (analysisId or skipped)
  // result.analysisId: first analysis id, or null
}
```

## Steps

A session records up to four steps one after another on the same screen, in
`config.steps` order (default `fullBody, face, hands, feet`):

| Step     | Live checks                                             | Tracking data uploaded (`landmarks.json`)                  |
|----------|---------------------------------------------------------|------------------------------------------------------------|
| fullBody | person in frame, one person only, lighting              | all 33 pose points per frame, grouped by region            |
| face     | one face, inside the box, big enough, lighting          | face box, landmarks, contours, head angles                 |
| hands    | lighting only                                           | none                                                       |
| feet     | lighting only                                           | none                                                       |

ML Kit has no hand or foot detector, so the hands and feet clips are **not
position-verified**; the server must judge them. Each step is uploaded as soon
as it is recorded, in the background; a short "Sending videos…" screen waits
for what is still uploading. `skippableSteps` (default face, hands, feet) get a
**Skip this step** button. `stepCameras` can switch camera on entering a step
(for example `{CaptureStep.feet: CameraKind.back}`). Tracking data is sampled
at the analysis rate (about 6-7 per second), each sample with a millisecond
timestamp. Coordinates are normalised to the upright image; when `mirrored` is
true they are mirrored with the video.

`open` runs the same check itself and returns `unsupported` without opening
the camera on a blocking problem. Blocking problems: wrong platform, old OS,
camera permission not declared (Android manifest / iOS `NSCameraUsageDescription`),
restricted camera access, no camera, ML Kit unavailable (for example Apple
Silicon simulators). Fixable: denied camera access (the screen offers **Open
Settings**), low storage. The capture screen keeps the display awake and
restores the previous setting on close.

Call `MovementCapture.purgeAll()` on logout and before login (never while a
capture screen is open).

## Modes and spoken prompts

`config.mode` serves two business models from one code base.

|                  | `assisted` (B2B, default)                | `selfGuided` (B2C)                     |
|------------------|------------------------------------------|----------------------------------------|
| Wording          | Addresses the helper ("Ask the patient…") | Addresses the user ("Step back until…") |
| Spoken prompts   | Off unless `voiceInAssisted: true`       | On when a voice is supplied            |
| Countdown        | 3 s                                      | 5 s                                    |
| Banner / countdown size | standard                          | larger                                 |

Pass a `MovementCaptureVoice` to `open(voice:)`. The package has no
text-to-speech dependency: the host speaks the already-translated strings in
the user's language (a Hindi user needs Hindi strings and a Hindi voice).
`speak` must interrupt anything still playing and neither method may throw.
Each event is spoken once; an unresolved problem repeats every
`voiceIssueRepeat`. A speaker button mutes and unmutes for the session.
Self-guided mode without a voice logs one warning and stays silent.

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

Called once per recorded step, one at a time. Return a non-empty analysis id;
throw on failure (the package shows Retry).
Retry policy (attempts, backoff) is the uploader's job. Stop when
`cancellation` fires. The package deletes the clip file after success.

`MovementClip` also carries `platform` (`android`/`ios`), `cameraKind`
(`external`/`front`/`back`), `fileMirrored` (true only for the iOS front
camera) and `liveChecks` (false when the recording ran without quality
checks), plus `sessionId`, `step`, `stepIndex`, `stepCount` and the optional
`landmarksFile`. `clip.formFields` gives every text field as multipart
strings (metadata first; package fields win a name clash).

## MovementCaptureConfig fields (defaults)

| Field                                                          | Default                                                                      |
|----------------------------------------------------------------|------------------------------------------------------------------------------|
| maxDuration (fullBody step)                                    | 30 s (clamped 5-30 s)                                                        |
| steps                                                          | [fullBody, face, hands, feet]                                                |
| stepDurations                                                  | {} (other steps 10 s, clamped 5-30 s)                                        |
| skippableSteps                                                 | {face, hands, feet}                                                          |
| stepCameras                                                    | {}                                                                           |
| faceMinWidthFraction                                           | 0.28                                                                         |
| countdown                                                      | null = 3 s (assisted) / 5 s (selfGuided)                                     |
| mode                                                           | CaptureMode.assisted                                                         |
| voiceInAssisted                                                | false                                                                        |
| voiceIssueRepeat                                               | 6 s                                                                          |
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
