# Running the lab on a phone while the webcam is plugged in

## Why Wi-Fi adb
The phone's single USB-C port is in host mode for the webcam, so a USB cable to
the laptop is not available. Use adb over Wi-Fi.

## Pair once
- Over USB, before plugging in the webcam: `adb tcpip 5555`, then `adb connect <ip>:5555`.
- Android 11+: Developer options, Wireless debugging, "Pair device with pairing code",
  then `adb pair <ip>:<pair-port>` and `adb connect <ip>:<port>`.

## Keep the connection up
- Developer options: turn on "Stay awake".
- MIUI: battery saver off for the app and for "Wireless debugging" (set "No restrictions").
- Give the phone a fixed IP in the router if possible.

## Debug from the terminal, without `--start-paused`
```sh
flutter run -d <ip>:5555 --debug
```
The IDE adds `--start-paused`. Flutter then starts the activity with the extra
`start-paused=true` (`flutter_tools/lib/src/android/android_device.dart:683`, Flutter
3.47.6) and the Dart isolate waits at start until the tool connects to the VM service
and resumes it (`run_hot.dart` reports this state as "paused (probably due to
--start-paused)"). If the VM-service connection over Wi-Fi fails, the app can sit on a
blank screen and the tool may end with `Application finished.`. Release builds have no
VM service, so they never wait. This is the likely cause, not proven for this device.

## If it still sits on a blank screen
1. `adb shell pidof com.medpredict.movement_capture_lab`. A number means the app is alive and waiting.
2. Try `flutter run -d <ip>:5555 --debug --no-dds`.
3. Or start the app from its launcher icon, then `flutter attach -d <ip>:5555`.
4. Check the VM-service port forward exists: `adb forward --list`.

## For device testing
`flutter run -d <ip>:5555 --release`, or a profile build started from the launcher icon.

## If the process is gone instead
```sh
adb shell dumpsys activity exit-info com.medpredict.movement_capture_lab | head -40
adb logcat -b crash -d
```
