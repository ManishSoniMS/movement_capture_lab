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

## 2026-10-26: Device support check (PROMPT.md, Revision 5)

**Touched:** package became a Flutter plugin (`android/` Kotlin, `ios/` Swift, channel `movement_capture/native`: `supportInfo`, `openAppSettings`, `setKeepScreenOn`; pubspec `flutter: plugin:`; minSdk 24, iOS 15.5, AVFoundation). New domain: `native_support_info.dart`, `support_report.dart` (`evaluateSupport`, pure), `capture_step.dart`, `result.dart` (`MovementCaptureResult`). New data: `native_bridge.dart`, `support_checker.dart` (timeouts, ML Kit probe cached on success only). `api.dart`: `checkSupport`, `openAppSettings`, `open` now returns `MovementCaptureResult`. `screen.dart`: `support` param, keep-screen-on, result popping, **Open Settings** on permission-denied. `controller.resume()` retries after Settings. New string `openSettings`. Lab: support-check section, result logging. Tests: `support_report_test.dart` (11).

**Why:** PROMPT.md paths (`packages/`, `apps/lab`, flat `src/`) mapped to the existing layers; `NativeSupportInfo` is in `domain` so the pure evaluator stays plugin-free, `MethodChannel` code is in `data`. Screen calls the static `NativeBridge` directly (no domain interface), a small deviation from the layer rule to match the prompt.

**Pros:** hosts can hide the feature; `open` can't crash on missing iOS plist entry; decision logic unit-tested. **Cons:** breaking `open` return type; extra native code to maintain; `screen.dart` depends on `data/native_bridge`. Tests were written together with the implementation, so no separate red run was recorded. Package tests (60) and analyze clean; `flutter build apk --debug` and `flutter build ios --no-codesign` succeed. V35-V41 (device checks) NOT run.

## 2026-10-26: Skeleton overlay (PROMPT.md, Revision 6)

**Files:** `domain/pose_topology.dart` (new), `presentation/skeleton_layer.dart` (new), `test/pose_topology_test.dart` (new); edited `domain/frame_metrics.dart` (`FrameCheck.overlay`), `domain/config.dart` (`showSkeleton`, `skeletonMinLikelihood`), `data/mlkit_frame_analyzer.dart`, `presentation/controller.dart` (`overlay` notifier, cleared when analysis stops or camera is released), `presentation/customization.dart` (four skeleton colours), `presentation/screen.dart`, `presentation/debug_overlay.dart` (`LandmarkLayer` removed); lab `lab_settings.dart` and `home_page.dart` (Show skeleton switch).

**Why this approach:** PROMPT put `pose_topology.dart` in an `analysis/` folder and imported ML Kit's `PoseLandmarkType`. The repo keeps ML Kit out of `domain/`, so the topology uses its own `PoseJoint` enum with the same 33 names. The analyzer maps by name (`PoseJoint.values.byName`), and a test checks the two name sets stay equal.

**Pros:** `domain` and `presentation` stay free of ML Kit; topology is unit-tested without a device. **Cons:** a second enum to keep in sync if ML Kit adds a landmark; the name-equality test catches that.

**Not verified:** V42-V46 need a device (alignment per camera, colours, smoothness, clearing). TDD red phase was a compile failure (missing types), not a behavioural failure.

## 2026-10-26: Face, hands and feet steps with tracking data (PROMPT.md, Revision 7)

**Files:** new `domain/face_snapshot.dart`, `domain/landmark_track.dart`, `presentation/step_uploads.dart`; tests `landmark_track_test.dart`, `step_uploads_test.dart`, `customization_test.dart`. Edited `domain/` (`capture_step` getters, `capture_issue` +`noFace`/`faceTooFar`, `config` steps/durations/skippable/stepCameras/`faceMinWidthFraction`, `frame_metrics`, `capture_state` Finishing/FinishFailed/SessionComplete replace Uploading/UploadFailed/Completed, `uploader` new `MovementClip` fields and `formFields`, `capture_storage.writeLandmarks`, `frame_analyzer` per-step factory), `data/mlkit_frame_analyzer.dart` (detectors per step), `data/file_capture_storage.dart`, `presentation/controller.dart`, `screen.dart`, `customization.dart`, `skeleton_layer.dart` (contours), `debug_overlay.dart`; lab uploaders, settings, home page; package README.

**Why this approach:** PROMPT.md rewrites the package into `analysis/ camera/ storage/ ...` folders and replaces the controller wholesale. The repo keeps `domain/ data/ presentation/` (CLAUDE.md), so the same behaviour went into the existing layers and the controller was edited in place, keeping the `storage`/`analyzerFactory` injection. `FaceSnapshot` keys landmarks and contours by ML Kit's enum names as strings, so `domain` stays free of ML Kit. The upload queue was pulled out of the controller into `StepUploads` so retry, cancel, ordering and progress are unit-tested with fakes; the prompt kept it inside the controller.

**Pros:** steps, skip, background upload and `landmarks.json` work without touching the ML Kit boundary; upload logic is testable. **Cons:** `FaceSnapshot` string keys are not checked against ML Kit's enums at compile time; controller step flow (advance, skip, camera switch per step, purge-once) is still untested because it creates `CameraController` directly. `MovementCaptureStatus.completed` now needs every recorded step uploaded; `Uploading`/`UploadFailed`/`Completed` states and `clip.deviceFields` are gone (breaking for hosts that used them).

**Not verified:** V47-V55 (full session, face checks, hands/feet, skipping, back camera, slow uploads, failure, cancel, JSON on iOS) need a device. TDD red phase was a compile failure (missing types and members), not a behavioural failure. 93 package tests pass, package analyze clean, root analyze only the 3 known infos.

## 2026-10-26: Assisted and self-guided modes with spoken prompts (PROMPT.md, Revision 8)

**Files:** new `domain/voice.dart` (`MovementCaptureVoice`), `presentation/speech_planner.dart`, `presentation/voice_guide.dart`, `test/speech_planner_test.dart`. Edited `domain/config.dart` (`CaptureMode`, nullable `countdown`, `effectiveCountdown`, `mode`, `voiceInAssisted`, `voiceIssueRepeat`, `speaks`), `presentation/controller.dart` (one line: `effectiveCountdown`), `presentation/customization.dart` (self-guided texts, voice texts, `*For(mode)` helpers, two icons), `presentation/screen.dart` (voice guide, mute button, mode wording, larger text and countdown), `api.dart` (`voice`), `movement_capture.dart`; tests `config_test.dart`, `customization_test.dart`; package README. Lab: `flutter_tts` dependency, `data/tts_voice.dart`, `domain/lab_settings.dart`, `presentation/home_page.dart` (Mode and voice section, countdown 0 = default), Android `TTS_SERVICE` query.

**Why this approach:** PROMPT.md uses a `voice/` folder and `apps/lab`. The repo keeps `domain/ data/ presentation/`, so the interface sits in `domain/` and the planner and guide in `presentation/` (they need `MovementCaptureStrings` and the controller). The lab's TTS wrapper is plugin code, so it went in the lab's `data/`. The planner is pure and takes `now` as an argument, so repeat timing is tested without timers.

**Pros:** no TTS dependency in the package; speech decisions are unit-tested; mute does not replay missed prompts. **Cons:** `countdown` is now nullable (hosts reading `config.countdown` must use `effectiveCountdown`); `VoiceGuide` and the screen wiring are untested because the controller needs a camera; the lab now depends on `flutter_tts`.

**Not verified:** V56-V62 need a device (audibility at 3 m, repeat timing, mute, Hindi voice, text size on a 360 px phone). No Android or iOS build was run for the new plugin. TDD red phase was a compile failure (missing types), not a behavioural failure. 107 package tests pass, package analyze clean, root analyze only the 3 known infos.

## 2026-10-26: Documentation set (PROMPT.md, Revision 9)

**Files:** `movement_capture/README.md` (replaced), new `movement_capture/ARCHITECTURE.md`, `movement_capture/DECISIONS.md`, `movement_capture/CHANGELOG.md`, new `.github/pull_request_template.md`, root `README.md` (replaced), `movement_capture/pubspec.yaml` (`version: 0.7.0`). No Dart code changed.

**Why this approach:** the files were written as given, with these changes because the repo differs from the prompt: (1) the package lives in `movement_capture/` and the lab app at the repo root, so `packages/movement_capture` and `apps/lab` became those paths and the git dependency example uses `path: movement_capture`; (2) the lab README and the repo map share the root `README.md` (one file, map first, lab guide below), since the lab has no folder of its own; (3) the ARCHITECTURE folder map shows the real `domain/ data/ presentation/` layout instead of `analysis/ camera/ storage/ ...`, with `step_uploads.dart` and `voice_guide.dart` listed; (4) the link to `PATCHES.md` is `../third_party/...` so it resolves from the package folder; (5) the package version was still `0.1.0` and is now `0.7.0`.

**Checks:** V63 compared the README config table with `MovementCaptureConfig` (names and defaults match), the upload table with `MovementClip.formFields`, and the `landmarks.json` shape with `LandmarkTrack`. V64: the quick start, uploader and voice snippets compiled in a scratch file in the lab (one `use_build_context_synchronously` info from my wrapper, nothing else); the file was removed. V65: every relative link in the docs resolves; mermaid rendering on GitHub not checked.

**Not done:** the `movement_capture-v0.7.0` tag. The prompt says to tag after the lab checks pass on a device, and none of V35-V62 has been run. The `landmarks.json` examples were not compared with a real inspection file (V55 needs a device).

## 2026-10-26: Skeleton alignment and missing hand/leg points (PROMPT.md, Revision 10)

**Files:** `movement_capture/lib/src/domain/config.dart`, `domain/camera_choice.dart`, `domain/frame_analyzer.dart`, `data/mlkit_frame_analyzer.dart`, `presentation/controller.dart`, `presentation/screen.dart`, `presentation/skeleton_layer.dart`; lab `lib/domain/lab_settings.dart`, `lib/presentation/home_page.dart`; tests `config_test.dart`, `camera_choice_test.dart`; docs `CHANGELOG.md`, `DECISIONS.md` (D-026 to D-028, D-011/D-012 marked superseded), package `README.md`, `ARCHITECTURE.md`, root `README.md`; `pubspec.yaml` 0.7.1.

**Why this approach:** the prompt's paths and file names (`analysis/frame_quality_analyzer.dart`, `apps/lab/...`) don't exist here, so the same edits went into the real files: the rotation rule stays in the domain function `analysisRotationDegrees` (now: override, else iOS 0, else the sensor/screen rule for every camera kind), the analyzer is `MlKitFrameAnalyzer`, and the interval reaches it through the existing `FrameAnalyzerFactory` as a new `interval:` argument. The controller reads the orientation the way `CameraPreview` does (recording, then paused, locked, device). Everything else follows the prompt as written.

**Pros/cons:** rotation matches the preview by construction, so no per-camera tuning. About 15 analyses/s costs more CPU; low-memory devices stay at 150 ms. `cameraRotationDegrees` and `analysisInterval` becoming nullable is a breaking change for hosts that read them (marked in the changelog).

**Checks:** red phase was a compile failure (missing `overlayFlipFor`, `effectiveAnalysisInterval`, nullable override). Package tests, package analyze and root analyze (3 known infos) results are in the commit run below. `dart format` touched unrelated files; those hunks were reverted.

**Not verified:** V66 to V71 need devices (alignment on each camera, left/right on front cameras, during recording, hand/leg visibility, analyses/s). Nothing here can run camera or ML Kit under `flutter test`. No Android or iOS build was run. The `movement_capture-v0.7.0` tag is still not created.

## 2026-10-26: MediaPipe hand tracking in the hands step (PROMPT.md, Revision 11)

**Files:** package `domain/hand_topology.dart` and `domain/frame_downscaler.dart` (new, pure Dart), `domain/capture_step.dart`, `capture_issue.dart` (`noHands`, `oneHand`), `config.dart` (`handTracking`, `requireBothHands`), `frame_metrics.dart`, `pose_topology.dart` (`OverlayFrame.hands`), `landmark_track.dart` (`addHands`), `support_report.dart` (`handTrackingUnavailable`); `data/native_bridge.dart`, `data/mlkit_frame_analyzer.dart`, `data/support_checker.dart`; `presentation/controller.dart`, `customization.dart`, `skeleton_layer.dart`, `debug_overlay.dart`. Native: Android `HandTracker.kt`, plugin edits, `tasks-vision:0.10.26`; iOS `HandTracker.swift`, plugin edits, podspec (`MediaPipeTasksVision`, resource bundle), `Package.swift` removed; model `hand_landmarker.task` in both asset folders; `MODELS.md`. Lab: two switches. Tests: new `frame_downscaler_test.dart`, `hand_topology_test.dart`; added cases in `landmark_track_test.dart`, `support_report_test.dart`, `config_test.dart`; `frame_check_test.dart` enum order updated. Docs: CHANGELOG 0.8.0, DECISIONS D-029, README, ARCHITECTURE. `pubspec.yaml` 0.8.0.

**Why this approach:** the prompt's `analysis/` and `platform/` folders don't exist here, so the pure code went into `domain/`, the channel calls into `data/native_bridge.dart`, and the hand logic into `MlKitFrameAnalyzer` (it was already the per-step analyzer behind the `FrameAnalyzer` interface). The Dart side converts the frame to a small upright RGBA image before the first `await`; native only wraps it. Gradle pin is 0.10.26, the version the prompt names, though Google Maven lists 1.1.1 as newest; the iOS pod resolved to 0.10.35.

**Pros/cons:** one tested conversion path for both platforms; hand tracking failing never fails the capture. Cost: about 8 MB model plus MediaPipe native libraries, a nearest-neighbour downscale per hand frame in Dart, and the iOS plugin is CocoaPods-only now.

**Checks:** red phase was a compile failure (missing types). 127 package tests pass, package analyze clean, root analyze only the 3 known infos. `flutter build apk --debug` and `flutter build ios --debug --no-codesign` both succeed with ML Kit and MediaPipe together (after `pod install --repo-update` in `ios/`).

**Not verified:** V72 to V76 need devices (skeleton quality, hand checks, fallback, left/right `side`, release size). Release builds were not made, so the size change is unmeasured. Tags `movement_capture-v0.7.0`, `v0.7.1` and `v0.8.0` are not created.

## 2026-10-26: Review before upload, retake, quit at any time (PROMPT.md, Revision 12)

**Files:** package `domain/review_samples.dart` (new: `TimedOverlay`, `overlayAt`), `domain/capture_state.dart` (`Reviewing`), `config.dart` (`reviewBeforeUpload`, `reviewMirrorFor`), `result.dart` (`CaptureStepResult.retakes`), `uploader.dart` (`retakes`, `reviewed` form fields); `presentation/controller.dart` (`acceptReview`, `retakeStep`, `hasUnsavedWork`, pending clip, review samples), `step_uploads.dart` (`hasUnfinished`), `speech_planner.dart`, `customization.dart`, `screen.dart` (quit confirmation, Cancel on every state, `onDone`), `review_view.dart` (new); `pubspec.yaml` 0.9.0 + `video_player`. Lab: review switch, retakes in the results log, `_r<n>` in inspection file names. Tests: new `review_samples_test.dart`; added cases in `config_test.dart`, `clip_test.dart`, `speech_planner_test.dart`, `step_uploads_test.dart`. Docs: CHANGELOG 0.9.0, DECISIONS D-030 and D-031 (D-020 note), README, ARCHITECTURE.

**Why this approach:** the prompt's `analysis/`, `upload/` and `_jobs` map onto this repo as `domain/` and `StepUploads`. The controller keeps the recorded clip in `_pendingClip` until the user chooses, and only then hands it to `StepUploads`, so a rejected clip never reaches the uploader. `hasUnsavedWork` asks `StepUploads.hasUnfinished`. `review_samples.dart` is in `domain/` because it is pure Dart.

**Pros/cons:** a bad clip can be rejected before it is sent; retakes are reported. Each step takes a few seconds longer and the camera reopens after review (about 1 s). The back gesture used to be ignored during uploads; it now quits (after a confirmation) and cancels them.

**Checks:** red phase was a compile failure (missing types and fields). Package tests, package analyze and root analyze (3 known infos) results are in the commit run.

**Not verified:** `ReviewView` and the controller's review flow need a device (V77 to V83): playback, skeleton sync, mirroring, backgrounding, quit in each state. Tags `v0.7.0`, `v0.7.1`, `v0.8.0` and `v0.9.0` are not created.

## 2026-10-30: Scan one hand or one foot (docs/prompts/kiosk-02-single-limb.md)

**Files:** package `domain/body_sides.dart` (new: `BodySide`, `SideChoice`, `SideStatus`, `handSideIssue`), `capture_issue.dart` (`showLeftHand`, `showRightHand`), `capture_step.dart` (`hasSides`), `config.dart` (`offerSideChoice`), `result.dart` (`CaptureStepResult.sideChoice`, `statusOf`), `uploader.dart` (`MovementClip.sideChoice`, `sides` form field for one-sided scans only), `frame_analyzer.dart` + `data/mlkit_frame_analyzer.dart` (side/mirror callbacks, hand check via `handSideIssue`), `presentation/controller.dart` (`awaitingSideChoice`, `chooseSides`, `sideChoiceFor`), `side_choice_view.dart` (new: `SideChoiceView`, `SideSummary`), `screen.dart`, `speech_planner.dart`, `voice_guide.dart`, `customization.dart`. Tests: new `body_sides_test.dart`, `side_choice_flow_test.dart`; added cases in `clip_test.dart`; `frame_check_test.dart` issue order updated.

**Why this approach:** the package records hands (and feet) as one clip with both sides in view, not one scan per side, so "skip the right side" is expressed as a `SideChoice` for the step. Handedness already exists (MediaPipe label plus `personSide`), so the wrong-hand prompt reuses it and handles mirrored frames; no new model. The decision is a pure function in `domain/`. The question is a controller flag, not a new `CaptureState`, so no existing exhaustive switch changes.

**Pros/cons:** both stays first, selected and the default; one extra tap per hands/feet step (`offerSideChoice: false` removes it). The feet step has no tracking, so a one-sided foot scan relies on the instruction text only. "Finish with left only" after the first side does not apply: both hands are in the same clip.

**Checks:** red phase was a compile failure (missing types). 156 package tests pass, package analyze clean, root analyze only the 3 known infos.

**Not verified:** needs a device: choice screen on a kiosk tablet, handedness prompt with the real USB camera (mirrored and not), upload with the `sides` field. Backend does not know `sides` yet.

## 2026-10-30: Modern tracking overlay (kiosk-03)

**Files:** `movement_capture/lib/src/domain/{one_euro_filter,overlay_smoother,preview_mapping,tracker_state,tracker_input}.dart`, `presentation/{tracker_guide,tracker_overlay}.dart`, `skeleton_layer.dart` (smoothing), `screen.dart` (overlay host), `customization.dart` (14 tracker strings + `trackerMessage`); tests `tracker_logic_test.dart`, `tracker_overlay_test.dart`.

**What:** Dimmed layer with a segmented guide ring (face oval, open hand, foot; left/right and both), six states (searching, not aligned, aligned, scanning, lost, done) that change colour, motion and text. One Euro smoothing on pose, face boxes and hand points. 300 ms debounce on state drops. Overlay sits outside `CameraPreview`, so tracking updates repaint only it. Reduced motion follows the system setting.

**Why this way:** Pure classes for filter, mapping, state machine and input derivation so they unit-test without a camera. Hints come only from `CaptureIssue`s and the face box, so no hint is shown that the pipeline cannot measure.

**Pros:** no new package or ML model; no logging or storage of frames. **Cons:** `mapImagePointToView` is tested but not yet used at runtime (the skeleton still sits inside the preview, which already maps coordinates); `done` is not triggered by any state; face mesh dots are not drawn (pipeline gives contours only); no perf numbers (no device).

## 2026-10-30: Remove tracking marks, simple capture quality status (kiosk-03-simple-capture-quality)

**Decisions for the team (top):** (1) This task replaces the "modern tracker" entry above: the tracker guide, smoothing, `SkeletonLayer` and review skeleton were deleted, as the brief says. A copy of the tracker files is in the session scratchpad only; none of it was ever committed. (2) `blockOnPoorQuality` defaults to **false**, so the strict flow (poor quality stops the countdown and aborts a recording, with restarts) is now off unless the host turns it on. That changes the default for every host. (3) Kept: the fixed safe-zone box (`_SafeZonePainter`, never moves). Removed: skeleton, face boxes and contours, hand points, tracker ring/oval/hand/foot guide. The detectors still run because their landmarks feed the uploaded landmark track; only the drawing is gone. (4) Thresholds are **unconfirmed** (nothing in the repo states model requirements): `minSharpness` 40, `maxMotion` 10, `faceMaxWidthFraction` 0.7, `bodyMinHeightFraction` 0.55, `bodyMaxHeightFraction` 0.92, `minInFrameShare` 0.9, `minCheckPassShare` 0.8, `minRecordedDuration` 3 s. `allowUseAnyway` default on. (5) The overall result is not added to the upload payload; `QualitySummary.toJson()` exists for when the backend agrees a field.

**Files:** new `domain/{luma_thumb,quality_status,quality_summary}.dart`, `presentation/quality_status_bar.dart`; changed `config.dart`, `frame_metrics.dart`, `capture_state.dart` (`Reviewing.quality`), `data/mlkit_frame_analyzer.dart`, `controller.dart` (`status` notifier, quality samples, gating switch), `screen.dart`, `review_view.dart`, `customization.dart` (strings, icons, `warningColor`); removed `skeleton_layer`, `tracker_*`, `one_euro_filter`, `overlay_smoother`, `preview_mapping`, `review_samples`, `OverlayFrame`, `showSkeleton`, `skeletonMinLikelihood`, skeleton colours. Lab: "Show skeleton" switch became "Block on poor quality". Tests: new `quality_check_test.dart`, `quality_widgets_test.dart`.

**How:** sharpness (Laplacian variance) and movement (mean frame difference) use a 160 px brightness copy built from the Y plane every `qualitySampleInterval` (300 ms); the last values are reused in between. Brightness reuses `LumaStats`; in-frame reuses the existing detector issues; distance uses face width / body height. `VerdictHold` shows a new verdict only after 500 ms. The status bar sits in a Column above the preview, never on it. The after-recording result is time-weighted over the samples and shown in the existing review screen.

**Pros/cons:** no new package or model; no frame or landmark stored or logged (only the previous thumb is held in memory). Detection still runs at the old 15/s rate because the landmark track needs it, so the "2-4 fps" limit applies to the pixel maths, not to ML Kit. The pixel maths run on the UI isolate (small: about 19k pixels at 3/s); not measured against an isolate. The summary only appears when `reviewBeforeUpload` is on and live checks ran. The camera-capability check (resolution/fps at open) and the "record and analyse at the same time" check (Step 6) were **not** done: the package already streams frames while recording and falls back to no live checks; that needs a device.

**Checks:** 186 package tests pass, package analyze clean, root analyze only the 3 known infos. Red phase was a compile failure (missing types).

**Not verified:** everything camera-related: real verdicts in the dark / moving / half out of frame, built-in vs USB camera, CPU and preview frame rate before/after, status bar layout on the kiosk tablet.

## Single scan type picker, show/hide camera details

**Decisions for the team (top):** (1) One scan type per session. The package already accepts a one-step `steps` list and returns one result per step, so no backend change is needed; the upload payload is unchanged. The lab's step checkboxes were replaced by the picker. (2) `showDetails` default is **on** (config value, unconfirmed); the team may want off for patients. (3) New dependency in the lab only: `shared_preferences` (BSD-3, Flutter team). The kiosk repo's own storage is not in this repo, so the lab uses the `SettingsStore` interface with a SharedPreferences implementation; the kiosk app should plug its existing storage in. (4) The "kiosk home page" is not in this repo; the lab home page stands in for it.

**Camera screen inventory.** Always shown: preview, safe-zone box, status area (task 03), main instruction, record/skip/cancel buttons, countdown, recording timer and progress bar, camera-chooser, notices, after-recording result. Details (hidden when off): step counter "Step n of m", debug metrics panel (`DebugMetricsPanel`, also needs `showDebugOverlay`). With details off the step icon and step title stay in the Checking banner. Not clearly either, put in Details: nothing else found. The camera name, rotation, resolution and fps are only in the debug panel.

**Files:** new `domain/scan_selection.dart`, `presentation/scan_type_picker.dart`, lab `domain/settings_store.dart`, `data/prefs_settings_store.dart`; changed `config.dart`, `customization.dart`, `screen.dart`, `movement_capture.dart`, lab `lab_settings.dart`, `home_page.dart`, `pubspec.yaml`. Tests: `scan_type_test.dart` (package), `test/settings_store_test.dart` (lab).

**Pros/cons:** the picker takes the selection from the host, so the host keeps navigation and the side-choice step stays in the package. Tiles are two flexible rows so all four fit without scrolling. Screen-level detail hiding cannot run under `flutter test` (camera); the quality code does not read `showDetails` (source guard).

**Not verified:** all manual kiosk checks (each scan type end to end, hands/feet side choices, toggle persistence after a real restart, uncluttered camera screen).
