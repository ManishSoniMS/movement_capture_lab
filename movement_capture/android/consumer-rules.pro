# Applied automatically to every app that depends on movement_capture
# (consumerProguardFiles in build.gradle.kts). Hosts need no extra setup.
#
# Without these, Android release builds (R8) break:
#   - ML Kit pose/face  -> support check: mlKitUnavailable
#     (InputImageConverterError, NullPointerException ... getClass())
#   - MediaPipe hands   -> support check: handTrackingUnavailable
#     (IllegalStateException: no caller found on the stack, from Flogger)
#   - WorkManager/Room  -> blank screen on launch (WorkDatabase_Impl stripped)
# These libraries load some of their own classes by name, which R8 cannot see.
#
# Deliberately broad (whole libraries). Cost: a slightly larger APK.
# Narrow only with a release-build device check after each change.

# --- ML Kit: pose + face detection and the shared vision code ---
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.odml.** { *; }
-keep class com.google_mlkit_** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**

# --- MediaPipe hand landmarker: native (JNI) code looks these up by name ---
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
# Flogger (MediaPipe's logger) finds its caller by class name on the stack.
# Renamed classes -> "no caller found on the stack" in Graph.<clinit> -> hands fail.
-keep class com.google.common.flogger.** { *; }
-dontwarn com.google.common.flogger.**

# --- WorkManager (pulled in by ML Kit): Room builds its database by reflection ---
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.** { *; }

# --- This plugin (registered by name from GeneratedPluginRegistrant) ---
-keep class com.medpredict.movement_capture.** { *; }

# --- Direct USB camera (org.uvccamera:lib) ---
# JNI looks these up by name
-keep class com.serenegiant.** { *; }
-keep class org.uvccamera.** { *; }
