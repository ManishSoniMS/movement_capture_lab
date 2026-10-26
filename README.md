# movement_capture_lab

| Folder                            | What                                                                                                      |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------|
| `movement_capture`                | The library. Start with its [README](movement_capture/README.md).                                         |
| `lib/`, `android/`, `ios/` (root) | Test and tuning app for real devices (the lab, described below)                                           |
| `third_party/camera_avfoundation` | Patched iOS camera plugin for iPad USB webcams ([PATCHES.md](third_party/camera_avfoundation/PATCHES.md)) |

Releases are tagged `movement_capture-vX.Y.Z`. See the [changelog](movement_capture/CHANGELOG.md).

---

# Movement Capture Lab

A development app for testing and tuning `movement_capture` on real devices. **Never ship it to patients.** It contains diagnostics, and an "inspection" uploader that keeps clips on the device.

## Run

```bash
flutter pub get
flutter run            # Android: Galaxy Tab S9 FE with the USB webcam
cd ios && pod install  # once, for iOS
```

Android 7+ (API 24) and iOS 15.5+. It needs a real device: the camera and ML Kit don't run in simulators.

## What's on the home screen

| Section            | Use                                                                                                  |
|--------------------|------------------------------------------------------------------------------------------------------|
| Support check      | Runs `checkSupport()` on launch; "Copy support report" for bug reports                               |
| Timing             | Full-body duration, countdown (0 = mode default), stability, grace, restarts, analysis rate          |
| Steps              | Pick steps, close-up duration, back camera for the feet step                                         |
| Mode and voice     | assisted / selfGuided, text-to-speech on/off, language                                               |
| Camera             | Rotation for USB camera checks, resolution, mirroring (Auto/On/Off), orientation, last chosen camera |
| Framing / Lighting | Live-tunable thresholds                                                                              |
| Upload             | Mock (succeeds) · Mock (always fails) · Keep clip for inspection · Real HTTP endpoint                |
| Tools              | Show skeleton, Debug overlay, Copy settings, Purge cache, Delete inspection clips                    |
| Results            | One line per run: status, analysis ID per step, settings used                                        |

The USB icon in the app bar opens **Camera diagnostics**. It compares what the Flutter plugin sees with what Android offers natively, and gives a verdict.

## Getting clips off the device

- **Android:** `adb pull /sdcard/Android/data/com.medpredict.movement_capture_lab/files/inspection`
- **iPad / iPhone:** Xcode → Window → Devices and Simulators → the lab app → Download Container → `AppData/Documents/inspection`

Inspection file names show platform, camera kind, mirroring and live-check state.

## Tuning on site

1. Turn the debug overlay on.
2. Run captures with real users, clothing and lighting.
3. Adjust the sliders until false alerts stop.
4. Tap **Copy current settings** and paste the line into the PR. Those values become the host app's config.

## iOS USB cameras

`third_party/camera_avfoundation` is a patched copy of the iOS camera plugin (see its `PATCHES.md`), applied through `dependency_overrides` in `pubspec.yaml`.
