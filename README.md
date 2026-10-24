# Movement Capture Lab

Test harness for the `movement_capture` package. Android 7+ (API 24) and iOS 15.5+.

## Getting clips off a device

- Android: `adb pull` from the app's external files `inspection/` folder.
- iPad/iPhone: Xcode, Window, Devices and Simulators, select the lab app,
  Download Container, then `AppData/Documents/inspection`.

Inspection file names show platform, camera kind, mirroring and live-check state.

## iOS USB cameras

`third_party/camera_avfoundation` is a patched copy of the iOS camera plugin
(see its `PATCHES.md`), applied through `dependency_overrides` in `pubspec.yaml`.
