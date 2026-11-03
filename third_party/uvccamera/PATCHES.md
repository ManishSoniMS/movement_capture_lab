# Lab patches to uvccamera 0.0.13

LAB ONLY and TEMPORARY. Copied from pub.dev `uvccamera` 0.0.13, applied through
`dependency_overrides` in the lab `pubspec.yaml`. Never used by `movement_capture/`.
Remove it when Part B replaces the plugin.

## Patch 1: pick the closest frame size (`UvcCameraPlatform.java`, `openCamera`)

Before:
```java
final var areaDelta = size.width * size.height - desiredFrameArea;          // int
Collections.sort(list, (l, r) -> Integer.compare(r.second, l.second));       // largest delta first
final var desiredFrameSize = list.get(0).first;
```
After:
```java
final long areaDelta = (long) size.width * size.height - (long) desiredFrameArea;
Collections.sort(list, (l, r) -> Long.compare(Math.abs(l.second), Math.abs(r.second)));
```
Why: the old sort put the largest size first for every preset, so `low` and
`medium` opened the camera's biggest mode (1080p MJPEG). The `min`/`max` presets use
`Integer.MIN_VALUE`/`MAX_VALUE` as the area, so the delta is computed as `long`
(an int would overflow). `min` and `max` now pick the smallest and largest size.

## Patch 2: read `previewMode` in `setPreviewMode` (`UvcCameraNativeMethodCallHandler.java`)

Before: `call.argument("mode")`. After: `call.argument("previewMode")`.
Why: the Dart side (`uvccamera_platform.dart`) sends the key `previewMode`, so the
native call always answered "mode is required".
