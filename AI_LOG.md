# AI decision log

## 2026-10-24: Clean Architecture split

**Touched:** `movement_capture/lib/src/` split into `domain/`, `data/`, `presentation/`; `api.dart` stays as facade. Lab app `lib/` split the same way. New interfaces `CaptureStorage`, `FrameAnalyzer`; implementations `FileCaptureStorage`, `MlKitFrameAnalyzer` (renamed from `MovementCaptureStorage` static class and `FrameQualityAnalyzer`). `FrameMetrics`/`FrameCheck`/`LandmarkPoint`/`UnsupportedFrameFormat` moved to `domain/frame_metrics.dart`. Controller now takes `storage` and `analyzerFactory` (defaults keep behaviour). Public API unchanged. New tests: `frame_check_test`, `capture_state_test`, `file_capture_storage_test`.

**Why:** controller hard-wired ML Kit and file access, so it couldn't be tested. Constructor injection with defaults, no DI package, keeps the package free of Riverpod/GetIt per its host-agnostic rules.

**Pros:** swappable analyzer/storage, pure logic testable (13 -> 20 tests), enforced import direction. **Cons:** more files; `camera` types still leak into `domain` (`CameraImage`, `ResolutionPreset` are public API); controller still creates `CameraController` directly, so state-machine flows remain untested without a camera gateway (next step).
