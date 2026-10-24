# AI decision log

## 2026-10-24: Clean Architecture split

**Touched:** `movement_capture/lib/src/` split into `domain/`, `data/`, `presentation/`; `api.dart` stays as facade. Lab app `lib/` split the same way. New interfaces `CaptureStorage`, `FrameAnalyzer`; implementations `FileCaptureStorage`, `MlKitFrameAnalyzer` (renamed from `MovementCaptureStorage` static class and `FrameQualityAnalyzer`). `FrameMetrics`/`FrameCheck`/`LandmarkPoint`/`UnsupportedFrameFormat` moved to `domain/frame_metrics.dart`. Controller now takes `storage` and `analyzerFactory` (defaults keep behaviour). Public API unchanged. New tests: `frame_check_test`, `capture_state_test`, `file_capture_storage_test`.

**Why:** controller hard-wired ML Kit and file access, so it couldn't be tested. Constructor injection with defaults, no DI package, keeps the package free of Riverpod/GetIt per its host-agnostic rules.

**Pros:** swappable analyzer/storage, pure logic testable (13 -> 20 tests), enforced import direction. **Cons:** more files; `camera` types still leak into `domain` (`CameraImage`, `ResolutionPreset` are public API); controller still creates `CameraController` directly, so state-machine flows remain untested without a camera gateway (next step).

## 2026-10-24: Camera detection and camera picker (PROMPT.md, Revision 2)

**Touched:** package: new `domain/camera_choice.dart` (`CameraChoice`, `buildCameraChoices`, `pickDefaultCamera`, `analysisRotationDegrees`); `config.dart` (`preferredCameraId`, `mirror{External,Front,Back}Preview`); `CameraFailure.notConnected` renamed `noCamera`; `FrameMetrics.rotationDegrees`; `MlKitFrameAnalyzer` takes a `rotationDegrees` callback; controller (`selectCamera`, `refreshCameras`, `canChangeCamera`, `usingTabletFallback`, `onCameraChanged`); `screen.dart` (camera button, bottom sheet, fallback notice, per-kind mirroring); strings/icons; debug overlay rotation line; `api.dart` + exports; `camera_android` dependency; README. Lab: `camera_android` + `camera_platform_interface` deps, `MainActivity.kt` diagnostics channel, new `camera_info_page.dart`, mirror switches and last-camera fields in settings/home. Tests: new `camera_choice_test.dart`, config defaults, `frame_check_test` updated. 33 tests pass; `flutter build apk --debug` succeeds.

**Why:** CameraX builds its camera list once and can drop USB cameras; `camera_android` (Camera2) asks Android each time. Selection and rotation rules sit in `domain` as pure functions so they are testable without a device. PROMPT.md was written for a flat layout (`apps/lab`, flat `src/`); files were mapped to the existing `domain/data/presentation` layers instead.

**Pros:** USB camera should be detected, tablet fallback, operator can switch, rules unit-tested. **Cons:** `camera_android` skips non-numeric camera ids; every host must list it directly; controller still builds `CameraController` itself, so `selectCamera`/fallback flows and the sheet UI are not unit-tested. Not verified on a device (V15-V20 from PROMPT.md still need the Galaxy Tab S9 FE and a webcam).
