# AI decision log

## 2026-10-24: Clean Architecture split

**Touched:** `movement_capture/lib/src/` split into `domain/`, `data/`, `presentation/`; `api.dart` stays as facade. Lab app `lib/` split the same way. New interfaces `CaptureStorage`, `FrameAnalyzer`; implementations `FileCaptureStorage`, `MlKitFrameAnalyzer` (renamed from `MovementCaptureStorage` static class and `FrameQualityAnalyzer`). `FrameMetrics`/`FrameCheck`/`LandmarkPoint`/`UnsupportedFrameFormat` moved to `domain/frame_metrics.dart`. Controller now takes `storage` and `analyzerFactory` (defaults keep behaviour). Public API unchanged. New tests: `frame_check_test`, `capture_state_test`, `file_capture_storage_test`.

**Why:** controller hard-wired ML Kit and file access, so it couldn't be tested. Constructor injection with defaults, no DI package, keeps the package free of Riverpod/GetIt per its host-agnostic rules.

**Pros:** swappable analyzer/storage, pure logic testable (13 -> 20 tests), enforced import direction. **Cons:** more files; `camera` types still leak into `domain` (`CameraImage`, `ResolutionPreset` are public API); controller still creates `CameraController` directly, so state-machine flows remain untested without a camera gateway (next step).

## 2026-10-24: Camera detection and camera picker (PROMPT.md, Revision 2)

**Touched:** package: new `domain/camera_choice.dart` (`CameraChoice`, `buildCameraChoices`, `pickDefaultCamera`, `analysisRotationDegrees`); `config.dart` (`preferredCameraId`, `mirror{External,Front,Back}Preview`); `CameraFailure.notConnected` renamed `noCamera`; `FrameMetrics.rotationDegrees`; `MlKitFrameAnalyzer` takes a `rotationDegrees` callback; controller (`selectCamera`, `refreshCameras`, `canChangeCamera`, `usingTabletFallback`, `onCameraChanged`); `screen.dart` (camera button, bottom sheet, fallback notice, per-kind mirroring); strings/icons; debug overlay rotation line; `api.dart` + exports; `camera_android` dependency; README. Lab: `camera_android` + `camera_platform_interface` deps, `MainActivity.kt` diagnostics channel, new `camera_info_page.dart`, mirror switches and last-camera fields in settings/home. Tests: new `camera_choice_test.dart`, config defaults, `frame_check_test` updated. 33 tests pass; `flutter build apk --debug` succeeds.

**Why:** CameraX builds its camera list once and can drop USB cameras; `camera_android` (Camera2) asks Android each time. Selection and rotation rules sit in `domain` as pure functions so they are testable without a device. PROMPT.md was written for a flat layout (`apps/lab`, flat `src/`); files were mapped to the existing `domain/data/presentation` layers instead.

**Pros:** USB camera should be detected, tablet fallback, operator can switch, rules unit-tested. **Cons:** `camera_android` skips non-numeric camera ids; every host must list it directly; controller still builds `CameraController` itself, so `selectCamera`/fallback flows and the sheet UI are not unit-tested. Not verified on a device (V15-V20 from PROMPT.md still need the Galaxy Tab S9 FE and a webcam).

## 2026-10-24: Works on any Android or iOS device (PROMPT.md, Revision 3)

**Touched:** package domain: `config.dart` (tri-state mirroring + `mirrorPreviewFor`, `CaptureOrientation`, `orientationsFor`, `allowRecordingWithoutLiveChecks`), `luma_stats.dart` (BGRA path, shared accumulator), `capture_state.dart` (`Recording.liveChecks`), `uploader.dart` (`MovementClip` platform/cameraKind/fileMirrored/liveChecks + `deviceFields`), `camera_choice.dart` (`isIOS` rotation rule). Data: `MlKitFrameAnalyzer` accepts NV21 and BGRA; `FileCaptureStorage.purgeAll` also cleans the iOS plugin folder (`pluginVideosDir` injectable). Presentation: controller (per-platform image format, record without live checks + watchdog, clip metadata), screen (orientation by screen size, narrow layout, notice), strings. Lab: tri-state mirror, orientation, no-live-checks setting, uploader fields, iOS-safe diagnostics page. `third_party/camera_avfoundation` vendored and patched; `dependency_overrides` in lab pubspec. READMEs. Tests added for BGRA luma, config, state, storage, clip, iOS rotation.

**Why:** PROMPT.md assumed flat files; mapped to the existing layers. Vendored copy came from the pub cache (resolved version is 0.10.3+1, not the prompt's example 0.11.1), so it matches what pub would resolve exactly. The patch is Swift (CameraPlugin.swift). iOS Info.plist and deployment target 15.5 were already in place. The rotation rule went into the pure `analysisRotationDegrees` so it is unit-tested.

**Pros:** iOS frames are checked, no double-mirroring, no mp4 left on iOS, phones get a usable layout, server learns mirroring/live-check state. **Cons:** a vendored plugin copy must be re-patched on `camera` upgrades; controller recording-fallback and screen layout are not unit-tested (no camera gateway yet); nothing verified on a device (V21-V28 need iPad, iPhone, phone, low-end Android). No iOS build was run.

## 2026-10-24: Fix "CameraController was used after being disposed" (PROMPT.md, Revision 4)

**Touched:** new `presentation/serial_queue.dart` + `test/serial_queue_test.dart`; `controller.dart` (public camera ops now enqueue; `...Impl` methods run inside the queue; `_countdownId`, `_transitionQueued`, `_suspended`; `_requestFail(epoch:/camera:)` for timers and frame callbacks; `dispose()` cancels upload before queuing `_teardownImpl`; `_open` re-checks the camera after `initialize()`); `screen.dart` lifecycle (release only on `paused`/`hidden`, ignore `inactive`/`detached`). Edited in place, not replaced: the prompt's controller predates the `storage`/`analyzerFactory` DI and `analysisRotationDegrees`, so those were kept.

**Why:** `inactive` fires for the permission prompt, so `suspend()` disposed the camera mid-`initialize()`. Overlapping async camera ops were the second cause; one serial queue plus epoch-stamped requests removes the overlap.

**Pros:** no camera use-after-dispose, shade/Control Center no longer kills recording, resume only reopens what suspend released. **Cons:** queued ops add latency (e.g. camera switch waits for a running open); `_tornDown` flag dropped (teardown runs once via dispose). Controller flows still untested (no camera gateway); V29-V34 need iPad/Tab S9 FE and were NOT run. 49 package tests pass, package analyze clean, root analyze only the 3 known infos.
