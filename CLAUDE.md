# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo layout

Two Flutter packages in one repo:

- `/` (`movement_capture_lab`): lab/test-harness app. Exercises the package on a real tablet. Code in `lib/`.
- `movement_capture/`: the reusable package under test (path dependency). Operator-assisted full-body video capture for kiosk tablets: live quality checks (ML Kit pose + face, luma), countdown, record up to 30 s, upload via host-supplied uploader, return an analysis id. Package README documents config defaults and host contract.

Both use Clean Architecture layers (see below). iOS and Android only; no web/desktop code.

## Commands

```sh
flutter pub get                      # app (also resolves the package)
flutter run                          # needs a real device (camera + ML Kit); Android minSdk >= 24
flutter analyze                      # root app; analysis_options excludes android/ ios/ build/
cd movement_capture && flutter analyze
cd movement_capture && flutter test                          # all package tests
cd movement_capture && flutter test test/quality_timer_test.dart   # single test file
cd movement_capture && flutter test --plain-name "<name>"    # single test by name
```

Root `test/` is empty; all tests live in `movement_capture/test/`. Baseline: package tests and package analyze are clean. Root `flutter analyze` has 3 known infos (`unintended_html_in_doc_comment` in `uploaders.dart`, deprecated `Radio` `groupValue`/`onChanged` in `home_page.dart`); don't add new ones.

## Workflow (TDD, zero regressions)

1. **Explore.** Read the affected code and `graphify-out/GRAPH_REPORT.md`. Run `cd movement_capture && flutter test` and `flutter analyze` (both packages) first. If the baseline fails, stop and report. State what the change touches.
2. **Red.** Write the failing test first (unit for domain/data, widget for UI). Run it; confirm it fails for the right reason (missing behaviour, not a compile or setup error).
3. **Green.** Minimum code to pass. Re-run the full suite.
4. **Refactor + document.** Small widgets, constructor DI, `///` dartdoc on public API and non-obvious logic. Append an entry to `AI_LOG.md` (files touched, why this approach, pros/cons).

Camera and ML Kit can't run under `flutter test`. Test through the domain interfaces with fakes; verify hardware paths on a device and say so when you couldn't.

## Clean Architecture

Package (`movement_capture/lib/src`) and lab app (`lib/`) both use `domain/`, `data/`, `presentation/`. Dependencies point inward: `presentation` and `data` import `domain`; `domain` imports neither; `presentation` never imports plugins directly except `camera`/Flutter UI.

Package:

- `domain/`: `CameraChoice`/`pickDefaultCamera`/`analysisRotationDegrees` (camera selection rules), `CaptureIssue`, sealed `CaptureState`, `MovementCaptureConfig`, `FrameMetrics`/`FrameCheck`/`LandmarkPoint`/`UnsupportedFrameFormat`, `LumaStats`, `QualityTimer`, upload contract (`MovementUploader`, `MovementClip`, `UploadCancellation`), and the interfaces `CaptureStorage` and `FrameAnalyzer`. No ML Kit, `path_provider` or widget imports. Exception: `camera` types (`CameraImage`, `ResolutionPreset`) and `DeviceOrientation` appear because they are part of the public API vocabulary.
- `data/`: `MlKitFrameAnalyzer` (implements `FrameAnalyzer`, the only ML Kit code) and `FileCaptureStorage` (implements `CaptureStorage`, the only code touching capture files and `path_provider`).
- `presentation/`: `MovementCaptureController`, `MovementCaptureScreen`, `debug_overlay.dart`, `customization.dart` (`MovementCaptureStrings/Icons/Style`).
- `api.dart`: public facade `MovementCapture.open / purgeAll / listCameras`. `lib/movement_capture.dart` is the only file hosts import.

The controller takes `storage:`, `analyzerFactory:` (called with `rotationDegrees:` callback) and `onCameraChanged:` constructor params (defaults: `FileCaptureStorage`, `MlKitFrameAnalyzer`), so tests inject fakes. Known gap: it still creates `CameraController` directly (no camera gateway yet), so controller flows can't be unit-tested without a device.

Lab app: `domain/lab_settings.dart` (`UploaderMode`, settings), `data/uploaders.dart`, `presentation/` (`home_page.dart`, `camera_info_page.dart`). Keep it thin; no business logic in the lab.

New code goes in the layer that fits. New plugin access needs a `domain` interface first, then a `data` implementation, injected into the controller.

## Package behaviour to preserve

`MovementCapture.open(context, config:, uploader:, ...)` pushes `MovementCaptureScreen`, returns `String? analysisId` (null = operator cancelled). `purgeAll()` wipes `<cache>/movement_capture/` (never call while a capture screen is open).

- Controller: ChangeNotifier owned by the screen State. Sealed `CaptureState`: Initializing → Checking → CountingDown → Recording → Uploading → Completed, plus CameraUnavailable / NeedsOperator / UploadFailed. An `_epoch` counter is bumped each phase so stale async ML results are discarded; guard flags (`_busyTransition`, `_disposed`, `_tornDown`) protect against races. Preserve this pattern when adding async work. Camera pick: preferred id if still present, else first USB (external) camera, else front, else back; NV21 stream, no audio. The operator may switch camera only in `Checking(armed: false)`, `NeedsOperator`, `CameraUnavailable` (`canChangeCamera`). `onCameraChanged` fires on operator picks only, never on automatic fallback. USB camera uses fixed `cameraRotationDegrees`; tablet cameras derive rotation from sensor orientation + screen. Preview mirroring is per camera kind (`mirror*Preview`), display only.
- `MlKitFrameAnalyzer`: per-frame pose/face detection + luma stats → `FrameMetrics` with a set of `CaptureIssue`s (priority = enum order: multiplePeople, noPerson, outOfFrame, tooDark, tooBright, backlit). Skips frames when busy or inside `analysisInterval`. Throws `UnsupportedFrameFormat` unless the frame is single-plane NV21.
- `QualityTimer`: debounces issues (`violationGrace`; `stableBeforeStart` is applied by the controller) so flicker doesn't interrupt capture.
- `MovementCaptureConfig` clamps `maxDuration` to 5–30 s and asserts `cameraRotationDegrees` in {0, 90, 180, 270}.

## Android camera implementation

Android must use `camera_android` (Camera2), not the default CameraX, which can fail to list USB cameras. Flutter only switches implementation when `camera_android` is a **direct dependency of the app**, so both the package and the lab list it; any host must too. It skips non-numeric camera ids (do not work around inside the package). The lab's Camera diagnostics page (`camera_info_page.dart` + `MainActivity.kt` channel `lab/camera_diagnostics`) shows the active implementation and Camera2 ids. That channel is lab only; never copy it into the package or kiosk app.

## Package hard rules (from its README)

The package must NOT: import Dio/Riverpod/GoRouter or host code (host passes a `MovementUploader`); hardcode user-facing text (use `MovementCaptureStrings`, English defaults) or colours/icons (inherit host `Theme`; override via `Style`/`Icons`); persist anything beyond `<cache>/movement_capture/`; decide consent, login or navigation. Host checks video consent before `open`. Package deletes the clip file after successful upload. State management in the package is `ChangeNotifier`; do not introduce Bloc/Riverpod/GetIt there.

## Lab app uploaders

`UploaderMode` has four values backed by three classes: `MockUploader` (`mock` succeeds; `mockFail` always fails, to test Retry UI; fake 2 s), `InspectionUploader` (LAB ONLY: copies clips to external files `inspection/` for adb pull), `HttpUploader` (Dio multipart POST, 3 attempts with backoff on network/5xx; the only place Dio is allowed). Backend contract is in the `HttpUploader` doc comment.

## Response format

1. **Game plan:** layers and files to create or modify.
2. **Execution:** test written → failed → implemented → passed.
3. **Trade-offs:** any new package or pattern, with pros, cons, alternatives.
4. **Verification:** `flutter test` and `flutter analyze` results, or what couldn't be run.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- After modifying code files in this session, run `python3 -c "from graphify.watch import _rebuild_code; from pathlib import Path; _rebuild_code(Path('.'))"` to keep the graph current
