# Design decisions

Each entry records a closed decision: what was decided, why, and what follows from it. New decisions are added at the end. A decision that is replaced keeps its entry, marked **Superseded by D-xxx**.

---

### D-001 · Standalone library, tested in a separate lab app
**Decision:** Build the capture feature as a Flutter package (`movement_capture`), with a lab app (the repository root) only for testing and tuning on real devices.
**Why:** The feature must plug into the kiosk app and the consumer app without copying code. Testing on the real tablet must not disturb the production app.
**Consequences:** The package must not depend on host code (D-002). Hosts upgrade by changing a git tag.

### D-002 · The library knows nothing about the host
**Decision:** No Dio, Riverpod, GoRouter or host imports. Upload, speech, text, icons and colours are injected (`MovementUploader`, `MovementCaptureVoice`, `MovementCaptureStrings`, `MovementCaptureIcons`, `MovementCaptureStyle`).
**Why:** Plug-and-play across apps with different stacks and design systems.
**Consequences:** Hosts write a small uploader and, for spoken prompts, a voice.

### D-003 · The device checks quality; the server analyses
**Decision:** On-device ML is used only as yes/no quality gates. All health analysis is server-side and reviewed by a qualified doctor.
**Why:** Models can be improved without app releases. Keeps the device light. Clinical responsibility stays with doctor review.
**Consequences:** The library makes no clinical claims. Whether the server's output counts as a regulated medical device (CDSCO SaMD) is for the product owner to assess.

### D-004 · Nothing persists on the device
**Decision:** Clips and landmark files are temporary files in `cache/movement_capture/`. They are deleted after upload, on restart or failure, on session end or cancel, and by `purgeAll()` at session start, logout and login.
**Why:** Shared kiosks, DPDP, and an earlier audit that flagged unencrypted local storage.
**Consequences:** State holds file paths, never bytes. See D-018 for when `purgeAll()` may run.

### D-005 · No audio
**Decision:** `enableAudio: false`. No microphone permission.
**Why:** Movement analysis doesn't need it, and conversations near the kiosk must not be recorded.

### D-006 · Live checks: what and how
**Decision:**
- **Full body:** 11 key body points inside a safe zone (7.5% inset) with likelihood ≥ 0.5.
- **One person:** face count ≤ 1. ML Kit pose tracks one person only, so faces are counted instead.
- **Lighting:** mean brightness, clipped share and centre/border ratio, read from the raw frame.

All thresholds are in config.
**Why:** Usable clips without training anything. The thresholds must be tunable on site.
**Consequences:** A second person facing away is not detected. That is accepted, since a helper is present in B2B and the server reviews clips.

### D-007 · Debouncing
**Decision:** A problem must last 0.4 s to count. Checks must pass for 1.5 s before the countdown. After 3 automatic restarts per step, ask for help.
**Why:** One bad frame must never stop a recording, and loops must end.

### D-008 · Android uses Camera2 (`camera_android`), not CameraX
**Decision:** Hosts add `camera_android` as a direct dependency.
**Why:** CameraX builds its camera list once and has been reported to miss USB cameras. Camera2 asks Android every time. It also supports frame streaming during recording.
**Consequences:** Camera2's plugin skips non-numeric camera IDs. The lab diagnostics page detects this.

### D-009 · Camera choice
**Decision:** Default order is first USB camera, then front, then back. The helper can switch before a step. `onCameraChanged` fires only on a manual pick, never on automatic fallback.
**Why:** A session without the webcam must not make the tablet camera "preferred" forever.

### D-010 · iPad USB webcams through a patched `camera_avfoundation`
**Decision:** Vendor the exact resolved version and add `.external` discovery on iPadOS 17+. Hosts apply it with `dependency_overrides`.
**Why:** The official plugin only lists built-in cameras.
**Consequences:** Re-vendor on every `camera` upgrade (see `PATCHES.md`). Remove once upstream supports it.

### D-011 · Frame format and rotation per platform
**Superseded by D-026 / D-027** (the frame format part still holds).
**Decision:**
- **Frame format:** Android NV21, iOS BGRA8888.
- **Rotation for ML Kit:** USB camera uses `cameraRotationDegrees`; iOS built-in uses the sensor orientation; Android built-in uses sensor ± screen orientation.

**Why:** ML Kit needs these. USB cameras don't rotate with the tablet.

### D-012 · Mirroring
**Superseded by D-026 / D-027**
**Decision:** Preview mirroring is configurable per camera type, with platform defaults (USB on; front on for Android, off for iOS; back off). Files are never changed. Uploads report `fileMirrored` (iOS front camera).
**Why:** The iOS plugin already mirrors the front camera in both the preview and the file.

### D-013 · Recording without live checks
**Decision:** If a device can't send frames while recording, keep recording without checks, show a notice and upload `liveChecks=false`. Configurable, so the kiosk can stay strict.
**Why:** "Works on every device" for the public app, without hiding reduced quality.

### D-014 · Orientation and layout
**Decision:** `auto`: tablets (shorter side ≥ 600) landscape, phones portrait. Narrow screens stack the banner and the buttons.
**Why:** A standing person fits a portrait phone. The kiosk stays landscape.

### D-015 · Lifecycle and concurrency
**Decision:** Release the camera only on `paused` / `hidden`, never on `inactive`. Serialise all camera operations in one queue. Requests carry an epoch.
**Why:** `inactive` fires for the iOS permission prompt and caused "CameraController used after disposed". Overlapping async operations caused races.

### D-016 · Support check, and `open()` refuses unsafe devices
**Decision:** `checkSupport()` never throws and never prompts. `open()` runs it and returns `unsupported` on blocking issues. The package is a plugin with native code for permission declarations, OS version, storage and memory.
**Why:** The feature must never crash a host, for example through a missing iOS permission entry.
**Consequences:** `open()` returns `MovementCaptureResult` (breaking change in 0.4.0).

### D-017 · Keep the screen awake
**Decision:** The display stays on while the capture screen is open; the previous setting is restored on close.
**Why:** Phones dim mid-recording. Kiosk apps may already keep the screen on, so only what the library set is undone.

### D-018 · `purgeAll()` only at session start, end, logout and login
**Decision:** Never purge mid-session. Failures and camera switches delete only the interrupted recording.
**Why:** Earlier steps' clips may still be waiting to upload.

### D-019 · Skeleton overlay
**Decision:** Draw all 33 pose points joined by lines, coloured by region (face, body, hands, feet), gliding between samples. It is independent of the debug overlay (`showSkeleton`).
**Why:** Shows what is tracked. It previously disappeared with the debug overlay, and plain dots were hard to read.

### D-020 · Multi-step session: full body, face, hands, feet
**Decision:** Separate clips per step. Hands and feet are lighting-checked only. Uploads run in the background, one per step, with a shared `sessionId`.
**Why:** Face and hand detail is too small in a full-body shot. ML Kit has no hand or foot detector on both platforms.
**Consequences:** The server must judge hands and feet clips itself. A fixed kiosk webcam needs `stepCameras` or a manual switch for the feet step.

### D-021 · Tracking data as `landmarks.json` (format version 1)
**Decision:** For full body and face, upload timestamped samples in normalised upright-image coordinates, grouped by region (see ARCHITECTURE.md).
**Why:** Gives the server face, hands and feet separately even from the full-body clip, and lets it align with the video.

### D-022 · Assisted (B2B) and self-guided (B2C) modes
**Decision:** One code base, two modes: wording, countdown (3 s / 5 s), text size, and spoken prompts on by default in self-guided.
**Why:** B2B always has a helper. B2C users are alone and can't read the screen from 2–3 m.

### D-023 · Speech through a host-supplied voice, planned by a pure planner
**Decision:** `MovementCaptureVoice` interface; `SpeechPlanner` speaks each event once and repeats unresolved problems every 6 s; the user can mute.
**Why:** No TTS dependency in the library, and the host controls languages. Elderly users need prompts that are neither silent nor nagging.

### D-024 · Consent stays with the host
**Decision:** The library never shows consent. The host must confirm the user has accepted the video-recording policy before `open()`.
**Why:** Consent and policy versions belong to the host's account system.

### D-025 · Documentation is part of every change
**Decision:** Each package change updates CHANGELOG.md. Each decision updates this file. Contract changes update README.md and ARCHITECTURE.md in the same PR.
**Why:** This is a plug-and-play library; integrators rely on the docs.

### D-026 · Rotation follows the preview, not the physical camera
**Decision:** Analysed frames get the rotation that makes them match the on-screen preview: iOS 0 (the plugin rotates frames itself); Android `(sensor ± screen)` using CameraPreview's own orientation source, for front, back and USB cameras. `cameraRotationDegrees` is only an override.
**Why:** The skeleton is drawn over the preview; any other rule misaligns it. The old fixed 0° for USB cameras and sensor-based rotation on iOS were both wrong.

### D-027 · Mirroring: system first, then optional display flip
**Decision:** Front cameras are already mirrored by the system on both platforms, so there is no extra flip by default; USB cameras get a mirror view. The skeleton gets its own flip only where frames and preview differ (Android front).
**Why:** The previous Android default mirrored the front preview twice and swapped the skeleton's left and right.

### D-028 · Faster, smoother skeleton
**Decision:** Analyse up to ~15 frames/s (150 ms on low-memory devices), run the full-body face count every 3rd analysis, glide 50 ms, and draw uncertain points faded down to likelihood 0.2 (the checks still need 0.5).
**Why:** At 6–7 analyses/s with a 150 ms glide the skeleton trailed movement, and hands and feet disappeared during motion.
