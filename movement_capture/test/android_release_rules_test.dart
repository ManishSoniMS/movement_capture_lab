import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android release-build keep rules.
///
/// R8 (release builds) removes classes that ML Kit, MediaPipe and WorkManager
/// load by name. Without these rules the support check reports
/// `mlKitUnavailable` / `handTrackingUnavailable`, or the app shows a blank
/// screen on launch. The rules ship with the package (consumerProguardFiles) so
/// every host gets them automatically.
void main() {
  final rules = File('android/consumer-rules.pro');
  final gradle = File('android/build.gradle.kts');

  test('package ships consumer-rules.pro', () {
    expect(rules.existsSync(), isTrue,
        reason: 'android/consumer-rules.pro is missing');
  });

  test('build.gradle.kts registers the consumer rules', () {
    expect(gradle.readAsStringSync(),
        contains('consumerProguardFiles("consumer-rules.pro")'));
  });

  group('rules keep the libraries loaded by name', () {
    const required = <String>[
      '-keep class com.google.mlkit.** { *; }',
      '-keep class com.google.android.gms.internal.mlkit_** { *; }',
      '-keep class com.google_mlkit_** { *; }',
      '-keep class com.google.mediapipe.** { *; }',
      '-keep class com.google.protobuf.** { *; }',
      '-keep class com.google.common.flogger.** { *; }',
      '-keep class androidx.work.impl.WorkDatabase_Impl { *; }',
      '-keep class * extends androidx.room.RoomDatabase { *; }',
      '-keep class com.medpredict.movement_capture.** { *; }',
      '-keep class com.serenegiant.** { *; }',
      '-keep class org.uvccamera.** { *; }',
    ];
    for (final line in required) {
      test(line, () {
        expect(rules.existsSync(), isTrue);
        expect(rules.readAsStringSync(), contains(line));
      });
    }
  });
}
