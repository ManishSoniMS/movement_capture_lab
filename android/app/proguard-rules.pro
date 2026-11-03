# Lab-only R8 rules. Keep rules for ML Kit, MediaPipe and WorkManager ship with
# the movement_capture package (movement_capture/android/consumer-rules.pro).
# Do not duplicate them here.

# LAB ONLY, TEMPORARY (kiosk-08 Part A): UVC test page.
# JNI looks these up by name.
-keep class com.serenegiant.** { *; }
-keep class org.uvccamera.** { *; }
