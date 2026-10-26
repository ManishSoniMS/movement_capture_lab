# movement_capture

A plug-and-play Flutter library that records short, quality-checked videos of a person for remote movement analysis:

- a **full-body** clip, plus optional close-ups of the **face**, **hands** and **feet**
- with **live checks** while recording: in frame, one person only, lighting
- with **tracking data** (body and face points) for the full-body and face clips
- and **nothing left on the device**: every clip is uploaded through your code, then deleted

It runs in two modes:

- **assisted** (B2B: a helper such as a kiosk operator is present)
- **self-guided** (B2C: the user is alone, guided by spoken prompts)

The library does **no medical analysis**. It captures, checks quality and hands the clips to your uploader. Analysis happens on your server.

---

## Contents

1. [Platform support](#platform-support)
2. [Installation](#installation)
3. [Quick start](#quick-start)
4. [Checking device support](#checking-device-support)
5. [The capture session](#the-capture-session)
6. [Uploading: your server contract](#uploading-your-server-contract)
7. [Modes and spoken prompts](#modes-and-spoken-prompts)
8. [Configuration reference](#configuration-reference)
9. [Text, icons and colours](#text-icons-and-colours)
10. [Privacy and file deletion](#privacy-and-file-deletion)
11. [Limitations](#limitations)
12. [Troubleshooting](#troubleshooting)
13. [Further reading](#further-reading)

---

## Platform support

| Device                                   | Built-in camera                                      | USB webcam                                                                    |
|------------------------------------------|------------------------------------------------------|-------------------------------------------------------------------------------|
| Android 7.0+ (API 24) phones and tablets | ✅                                                   | ✅ where that device's Android offers USB cameras to apps (many phones don't) |
| iPad with USB-C, iPadOS 17+              | ✅                                                   | ✅ (needs the patched iOS camera plugin, see Installation)                    |
| iPad with Lightning, or iPadOS < 17      | ✅                                                   | ❌ (not supported by Apple)                                                   |
| iPhone, iOS 15.5+                        | ✅                                                   | ❌ (not supported by Apple)                                                   |
| Web, desktop, simulators                 | ❌ (the support check reports this; nothing crashes) | ❌                                                                            |

When no USB camera is connected, the front camera is used automatically, with a notice.

---

## Installation

### 1. Dependencies (your app's `pubspec.yaml`)

```yaml
dependencies:
  movement_capture:
    git:
      url: <private repo URL>
      path: movement_capture
      ref: movement_capture-v0.7.0

  # REQUIRED on Android: selects the Camera2 camera implementation.
  # Without it Android uses CameraX, which may not list USB webcams.
  camera_android: ^0.10.10

dependency_overrides:
  # REQUIRED for USB webcams on iPad: patched iOS camera plugin.
  # Without it iPads use only their built-in cameras.
  camera_avfoundation:
    git:
      url: <private repo URL>
      path: third_party/camera_avfoundation
      ref: movement_capture-v0.7.0
```

Both lines must be in **your app's** pubspec. Flutter ignores them inside a library.

### 2. Android

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-feature android:name="android.hardware.camera.external" android:required="false" />
```

- `minSdk` must be **24** or higher.
- Don't declare `RECORD_AUDIO` for this feature; audio is never recorded.
- **Kiosks managed by an MDM** (for example Headwind MDM): pre-grant the CAMERA permission to the app.

### 3. iOS

`ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera records a short movement video for your doctor's assessment.</string>
```

`ios/Podfile`: `platform :ios, '15.5'`. Also set the Runner target's iOS Deployment Target to 15.5, then run `pod install`.

> Without `NSCameraUsageDescription`, iOS kills the app the moment the camera starts. `checkSupport()` detects a missing entry and blocks the feature instead.

### 4. If you use spoken prompts on Android 11+

If your voice implementation uses the system text-to-speech engine (for example `flutter_tts`), add to the manifest:

```xml
<queries>
  <intent>
    <action android:name="android.intent.action.TTS_SERVICE" />
  </intent>
</queries>
```

---

## Quick start

```dart
import 'package:movement_capture/movement_capture.dart';

// 1. Decide whether to offer the feature at all.
final support = await MovementCapture.checkSupport();
if (!support.canRun) {
  log(support.describe()); // keep for support tickets
  return;                  // hide the button
}

// 2. Run a session (after the user accepted the video-recording policy).
final result = await MovementCapture.open(
  context,
  config: MovementCaptureConfig(
    maxDuration: Duration(seconds: fullBodySeconds), // full-body step, 5–30 s
    metadata: {'chatSessionId': chat.id},            // sent with every clip
    mode: CaptureMode.assisted,                      // or selfGuided (B2C)
  ),
  uploader: MyUploader(dio),                         // your server call
);

// 3. Use the result.
switch (result.status) {
  case MovementCaptureStatus.completed:
    for (final step in result.steps) {
      // step.step, step.analysisId (null if skipped), step.skipped
    }
  case MovementCaptureStatus.cancelled:   // left early; uploaded steps keep their IDs
    break;
  case MovementCaptureStatus.unsupported: // see result.support
    break;
}

// 4. On logout and before login:
await MovementCapture.purgeAll();
```

A minimal uploader:

```dart
class MyUploader implements MovementUploader {
  MyUploader(this._dio);
  final Dio _dio;

  @override
  Future<String> upload(
    MovementClip clip, {
    required void Function(double progress) onProgress,
    required UploadCancellation cancellation,
  }) async {
    final token = CancelToken();
    unawaited(cancellation.whenCancelled.then((_) => token.cancel()));
    final form = FormData.fromMap({
      'video': await MultipartFile.fromFile(clip.file.path,
          filename: 'movement.mp4', contentType: DioMediaType.parse('video/mp4')),
      if (clip.landmarksFile != null)
        'landmarks': await MultipartFile.fromFile(clip.landmarksFile!.path,
            filename: 'landmarks.json',
            contentType: DioMediaType.parse('application/json')),
      ...clip.formFields,
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/movement-analysis/videos',
      data: form,
      cancelToken: token,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress(sent / total);
      },
    );
    final id = response.data?['analysisId'];
    if (id is! String || id.isEmpty) throw StateError('missing analysisId');
    return id;
  }
}
```

Add retries (for example 3 attempts on network errors and 5xx) inside your uploader. The library only offers a Retry button when your uploader throws.

---

## Checking device support

`MovementCapture.checkSupport()` **never throws** and never asks for camera permission. `open()` runs it again itself and refuses to open the camera on a blocking problem, so the feature can't crash a host that forgets to call it.

| Property                  | Meaning                                                                                                                                                        |
|---------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `canRun`                  | `false` = a **blocking** problem. Don't offer the feature.                                                                                                     |
| `readyNow`                | `false` = something the **user can fix** (camera access off, storage low). `open()` still works and guides them, for example with an **Open Settings** button. |
| `issues`                  | Every finding, each with a `code`, `severity` and an English `message` for logs                                                                                |
| `describe()` / `toJson()` | For logs and bug reports                                                                                                                                       |

| Code                          | Severity                                   | Cause                                                                                                                                      |
|-------------------------------|--------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| `unsupportedPlatform`         | blocking                                   | Not Android or iOS                                                                                                                         |
| `osTooOld`                    | blocking                                   | Android < API 24, iOS < 15.5                                                                                                               |
| `cameraPermissionNotDeclared` | blocking                                   | Missing `CAMERA` (manifest) or `NSCameraUsageDescription` (Info.plist)                                                                     |
| `cameraAccessBlocked`         | user-fixable / blocking                    | iOS: denied (fixable) or restricted by device policy (blocking)                                                                            |
| `noCamera`                    | blocking                                   | No usable camera                                                                                                                           |
| `mlKitUnavailable`            | blocking                                   | Google ML Kit failed to load (for example Apple Silicon simulators)                                                                        |
| `lowStorage`                  | user-fixable                               | Less than 200 MB free                                                                                                                      |
| `checkFailed`                 | blocking                                   | Part of the check failed. On iOS this includes native info being unavailable, because the camera permission entry can't then be confirmed. |
| `noUsbCamera`                 | warning (blocking with `requireUsbCamera`) | No USB webcam connected                                                                                                                    |
| `noFrontCamera`               | warning                                    | The fallback will use the back camera                                                                                                      |
| `lowMemoryDevice`             | warning                                    | Live checks may run slowly                                                                                                                 |
| `runningOnSimulator`          | warning                                    |                                                                                                                                            |
| `nativeInfoUnavailable`       | warning (Android)                          | Native details couldn't be read                                                                                                            |

Pass `SupportRequirements(requireUsbCamera: true)` to `checkSupport()` and `open()` if a deployment must have a USB webcam (for example kiosks).

---

## The capture session

A session records the steps in `config.steps` (default: full body, face, hands, feet), one after another on the same screen:

1. The banner shows **"Step 2 of 4 · Face"** and the instruction.
2. The helper (or user) taps **Start**. The library waits until every check has passed for 1.5 s, counts down, and records.
3. If a check fails for more than 0.4 s while recording, the clip is deleted and recording restarts automatically. After 3 restarts it asks for help.
4. The finished clip is **uploaded in the background** while the next step is filmed.
5. After the last step, a short "Sending videos…" screen waits for any uploads still running.

| Step       | Live checks                                             | Tracking data                                                                        |
|------------|---------------------------------------------------------|--------------------------------------------------------------------------------------|
| `fullBody` | 11 key body points inside the box; one person; lighting | 33 body points per sample, grouped into face, body, left/right hand, left/right foot |
| `face`     | One face, inside the box, close enough; lighting        | Face box, 10 landmarks, 15 contours, head angles                                     |
| `hands`    | Lighting only                                           | None                                                                                 |
| `feet`     | Lighting only                                           | None                                                                                 |

Face, hands and feet are skippable by default. The skeleton overlay draws face, hands, feet and body in different colours. Its visibility is independent of the debug overlay.

---

## Uploading: your server contract

Your `MovementUploader.upload` is called **once per recorded step**, one at a time. `clip.formFields` contains all text fields:

| Field                     | Example                                | Meaning                                                               |
|---------------------------|----------------------------------------|-----------------------------------------------------------------------|
| *(your metadata)*         | `chatSessionId=…`                      | From `config.metadata`                                                |
| `sessionId`               | `3f9c…3f40`                            | Same for every step of one session                                    |
| `step`                    | `fullBody` / `face` / `hands` / `feet` |                                                                       |
| `stepIndex` / `stepCount` | `0` / `4`                              | Position in the session (0-based)                                     |
| `durationMs`              | `30012`                                | Actual recorded length                                                |
| `resolutionPreset`        | `high`                                 | Usually 720p                                                          |
| `capturedAt`              | `2026-10-26T09:12:03.120Z`             | UTC                                                                   |
| `platform`                | `android` / `ios`                      |                                                                       |
| `cameraKind`              | `external` / `front` / `back`          |                                                                       |
| `fileMirrored`            | `true` / `false`                       | `true` for the iOS front camera: **the video is mirrored**            |
| `liveChecks`              | `true` / `false`                       | `false` = this device couldn't check while recording; treat with care |

Files: `clip.file` (MP4, H.264, **no audio**) and, for full body and face, `clip.landmarksFile` (`landmarks.json`, format in [ARCHITECTURE.md](ARCHITECTURE.md#landmarksjson-format-version-1)).

Return the server's analysis ID. Throw on failure.

---

## Modes and spoken prompts

|                | `CaptureMode.assisted` (B2B)          | `CaptureMode.selfGuided` (B2C) |
|----------------|---------------------------------------|--------------------------------|
| Wording        | "Ask the patient to…"                 | "Step back until…"             |
| Spoken prompts | Off (on with `voiceInAssisted: true`) | On, when you pass a `voice`    |
| Countdown      | 3 s                                   | 5 s                            |
| Text size      | Large                                 | Larger                         |

Spoken prompts need a voice implementation. The library has no text-to-speech dependency:

```dart
class TtsVoice implements MovementCaptureVoice {
  TtsVoice({required this.language});
  final String language;
  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;

  @override
  Future<void> speak(String text) async {
    try {
      await (_ready ??= _tts.setLanguage(language));
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

await MovementCapture.open(context,
    config: MovementCaptureConfig(mode: CaptureMode.selfGuided, /* … */),
    uploader: uploader,
    strings: hindiStrings,        // the voice speaks these texts
    voice: TtsVoice(language: 'hi-IN'));
```

The voice speaks exactly the texts in `MovementCaptureStrings`. For Hindi, pass Hindi strings **and** use a Hindi voice. Users can mute the voice from the screen.

---

## Configuration reference

All fields of `MovementCaptureConfig` (all optional):

| Field                                                                | Default                         | Meaning                                                                                                          |
|----------------------------------------------------------------------|---------------------------------|------------------------------------------------------------------------------------------------------------------|
| `maxDuration`                                                        | 30 s                            | Full-body step length (clamped to 5–30 s)                                                                        |
| `steps`                                                              | `[fullBody, face, hands, feet]` | Steps in order (duplicates removed; empty = full body only)                                                      |
| `stepDurations`                                                      | `{}` (10 s each)                | Lengths of the other steps (5–30 s)                                                                              |
| `skippableSteps`                                                     | `{face, hands, feet}`           | Steps that show "Skip this step"                                                                                 |
| `stepCameras`                                                        | `{}`                            | Camera type to switch to when a step starts, e.g. `{CaptureStep.feet: CameraKind.back}`                          |
| `mode`                                                               | `assisted`                      | `assisted` (B2B) or `selfGuided` (B2C)                                                                           |
| `voiceInAssisted`                                                    | `false`                         | Also speak in assisted mode                                                                                      |
| `voiceIssueRepeat`                                                   | 6 s                             | How often an unresolved problem is repeated aloud                                                                |
| `countdown`                                                          | `null` (3 s / 5 s by mode)      | Countdown before recording                                                                                       |
| `stableBeforeStart`                                                  | 1.5 s                           | Checks must pass this long before the countdown                                                                  |
| `violationGrace`                                                     | 0.4 s                           | A problem must last this long to count                                                                           |
| `maxRestarts`                                                        | 3                               | Automatic restarts per step before asking for help                                                               |
| `resolution`                                                         | `ResolutionPreset.high`         | Usually 720p                                                                                                     |
| `preferredCameraId`                                                  | `null`                          | Camera chosen last time (from `onCameraChanged`)                                                                 |
| `cameraRotationDegrees`                                              | 0                               | USB camera image rotation for the checks (0/90/180/270)                                                          |
| `mirrorExternalPreview` / `mirrorFrontPreview` / `mirrorBackPreview` | `null` (platform default)       | Display-only mirroring                                                                                           |
| `orientation`                                                        | `auto`                          | `auto` (tablets landscape, phones portrait), `landscape`, `portrait`                                             |
| `allowRecordingWithoutLiveChecks`                                    | `true`                          | If the device can't check while recording: record anyway and report `liveChecks=false` (`false` = show an error) |
| `showSkeleton`                                                       | `true`                          | Draw the tracked skeleton                                                                                        |
| `skeletonMinLikelihood`                                              | 0.5                             | Hide uncertain points                                                                                            |
| `safeZoneInset`                                                      | 0.075                           | Box margin at each edge (wide-angle lens distortion)                                                             |
| `minLandmarkLikelihood`                                              | 0.5                             | Confidence needed for the 11 key body points                                                                     |
| `faceMinWidthFraction`                                               | 0.28                            | Face step: minimum face width as a share of the frame                                                            |
| `minMeanLuma` / `maxMeanLuma`                                        | 60 / 200                        | Too dark / too bright (0–255)                                                                                    |
| `maxClippedFraction`                                                 | 0.25                            | Share of nearly black/white pixels allowed                                                                       |
| `minCenterToBorderLuma`                                              | 0.6                             | Below this, "backlit"                                                                                            |
| `analysisInterval`                                                   | 150 ms                          | Time between analysed frames                                                                                     |
| `metadata`                                                           | `{}`                            | Sent with every clip                                                                                             |
| `restoreOrientations`                                                | `[]`                            | Orientations to restore on close (empty = system default)                                                        |

Other `open()` parameters: `strings`, `icons`, `style`, `requirements`, `voice`, `showDebugOverlay` (live numbers for tuning; keep it off in production), and `onCameraChanged` (fires only when someone picks a camera; store `camera.name` and pass it back as `preferredCameraId`).

Tune the thresholds on site with the lab app (the repository root). It has sliders for each one and copies the final values as one line.

---

## Text, icons and colours

- **`MovementCaptureStrings`**: every text, with English defaults. Mode-specific texts come in pairs, such as `stepInstructionFace` (assisted) and `selfStepInstructionFace` (self-guided). Templates use `{n}`, `{total}`, `{step}`, `{elapsed}`, `{percent}`. Pass translations from your l10n system, and have clinical wording reviewed by native speakers.
- **`MovementCaptureIcons`**: every icon. Pass your own icon-font glyphs.
- **`MovementCaptureStyle`**: error, active and skeleton colours. Anything left `null` comes from your app's `ColorScheme`: error, primary; skeleton body = primary, face = tertiary, hands = secondary, feet = inversePrimary.

Touch targets are at least 56 dp and texts are large by design (elderly users).

---

## Privacy and file deletion

- **Audio is never recorded.**
- Videos and `landmarks.json` exist only as temporary files in the app's cache folder (`movement_capture/`). The library deletes them:
  - after each successful upload
  - when a recording is restarted or interrupted
  - when the session ends or is cancelled
  - at the start of every session (leftovers from a crash)
  - whenever you call `MovementCapture.purgeAll()`. **Call it on logout and before login.**
- On iOS the camera plugin records into the app's `tmp/camera/videos/`. `purgeAll()` cleans that folder too.
- The library never asks for consent. **Your app must obtain consent for video recording before calling `open()`.** Under DPDP, sending a video to your server is processing personal data, even though nothing stays on the device.

---

## Limitations

- **Hands and feet close-ups are not position-checked**, because ML Kit has no hand or foot detector. Your server must judge their usability.
- Full-body tracking has only 3–4 points per hand and foot.
- Tracking data is sampled at the analysis rate (about 6–7 per second), with timestamps.
- 2D camera only: depth (walking towards the camera) is not measured.
- Pose accuracy varies with clothing (sarees, dhotis), walking aids and lighting. Tuning and model training are the server's concern.
- USB webcams: see [Platform support](#platform-support).

---

## Troubleshooting

| Symptom                                              | Likely cause and fix                                                                                                                                                                                    |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| USB webcam not listed on Android                     | `camera_android` missing from **your app's** pubspec (check: `CameraPlatform.instance` should be `AndroidCamera`). Or the device's Android doesn't offer USB cameras. Use the lab's Camera diagnostics. |
| USB webcam not listed on iPad                        | `camera_avfoundation` override missing, a Lightning iPad, or iPadOS < 17                                                                                                                                |
| App killed when the camera opens (iOS)               | `NSCameraUsageDescription` missing. `checkSupport()` would have blocked it.                                                                                                                             |
| "This camera cannot check the video while recording" | The device can't stream frames during recording and `allowRecordingWithoutLiveChecks` is false. Choose another camera or allow recording without checks.                                                |
| Skeleton offset or rotated                           | Wrong `cameraRotationDegrees` for a USB camera. Set it so the debug overlay's points sit on the body.                                                                                                   |
| Preview mirrored the wrong way                       | Override `mirror…Preview` for that camera type                                                                                                                                                          |
| Frequent "Too dark" / "Backlit"                      | Tune `minMeanLuma` and `minCenterToBorderLuma` on site                                                                                                                                                  |
| Phone dims during recording                          | Shouldn't happen: the screen is kept awake while the capture screen is open. Report it.                                                                                                                 |

---

## Further reading

- [ARCHITECTURE.md](ARCHITECTURE.md): internals, state machine, concurrency, data formats
- [DECISIONS.md](DECISIONS.md): why things are the way they are
- [CHANGELOG.md](CHANGELOG.md): version history and breaking changes
- [`third_party/camera_avfoundation/PATCHES.md`](../third_party/camera_avfoundation/PATCHES.md): the iOS plugin patch
