import 'package:camera/camera.dart';

import 'native_support_info.dart';
import 'usb_video_device.dart';

enum SupportSeverity {
  /// The feature cannot run on this device. Don't offer it.
  blocking,

  /// The feature can run once the user changes something (Settings, storage).
  userFixable,

  /// Informational only.
  warning,
}

enum SupportIssueCode {
  unsupportedPlatform,
  osTooOld,
  cameraPermissionNotDeclared,
  cameraAccessBlocked,
  noCamera,
  mlKitUnavailable,
  handTrackingUnavailable,
  lowStorage,
  checkFailed,
  noUsbCamera,
  noFrontCamera,
  lowMemoryDevice,
  runningOnSimulator,
  nativeInfoUnavailable,

  /// Warning: a USB video device is attached that Camera2 does not list. The
  /// package opens it directly.
  usbDirectInUse,

  /// User-fixable: Android has not granted access to the USB camera yet.
  usbPermissionNeeded,

  /// Warning: a video device is attached but cannot be used directly (native
  /// library missing for this ABI, or the open probe failed).
  usbDirectUnavailable,

  /// Warning: the probe opened the camera but no frame arrived in 3 s.
  usbNoFrames,
}

/// Outcome of the optional open probe (`checkSupport(probeUsb: true)`).
enum UsbProbeResult { notRun, ok, noFrames, failed }

class SupportIssue {
  const SupportIssue(this.code, this.severity, this.message);

  final SupportIssueCode code;
  final SupportSeverity severity;

  /// Developer-facing English explanation, for logs. Not for end users.
  final String message;

  Map<String, Object?> toJson() =>
      {'code': code.name, 'severity': severity.name, 'message': message};

  @override
  String toString() => '[${severity.name}] ${code.name}: $message';
}

/// What the host requires. Defaults suit both the kiosk and the public app.
class SupportRequirements {
  const SupportRequirements({
    this.minAndroidSdk = 24,
    this.minIosVersion = const [15, 5],
    this.minFreeBytes = 200 * 1024 * 1024,
    this.requireUsbCamera = false,
    this.lowMemoryBytes = 3 * 1000 * 1000 * 1000,
  });

  final int minAndroidSdk;
  final List<int> minIosVersion;
  final int minFreeBytes;
  final bool requireUsbCamera;

  /// Devices with less RAM than this get a lowMemoryDevice warning.
  final int lowMemoryBytes;
}

class SupportReport {
  const SupportReport({
    required this.platform,
    required this.issues,
    required this.checkedAt,
    this.osVersion,
    this.deviceModel,
    this.cameras = const [],
    this.cameraAuthorization,
    this.freeBytes,
    this.totalMemoryBytes,
    this.mlKitAvailable = false,
    this.handTrackingAvailable = true,
    this.usbVideoDevices = const [],
    this.usbDirectAvailable = false,
  });

  /// USB devices with a video interface, as the native side lists them.
  final List<UsbVideoDevice> usbVideoDevices;

  /// False when the direct-USB native library cannot load on this device.
  final bool usbDirectAvailable;

  /// "android", "ios", "web", or another platform name.
  final String platform;
  final String? osVersion;
  final String? deviceModel;
  final List<CameraDescription> cameras;
  final String? cameraAuthorization;
  final int? freeBytes;
  final int? totalMemoryBytes;
  final bool mlKitAvailable;

  /// False when the MediaPipe hand model could not load (hands step falls
  /// back to lighting checks).
  final bool handTrackingAvailable;
  final List<SupportIssue> issues;
  final DateTime checkedAt;

  /// False if any blocking issue exists. Don't offer the feature.
  bool get canRun => !issues.any((i) => i.severity == SupportSeverity.blocking);

  /// True if nothing at all stands in the way (only warnings, if anything).
  bool get readyNow =>
      issues.every((i) => i.severity == SupportSeverity.warning);

  bool has(SupportIssueCode code) => issues.any((i) => i.code == code);

  int get usbCameraCount => cameras
      .where((c) => c.lensDirection == CameraLensDirection.external)
      .length;

  Map<String, Object?> toJson() => {
        'platform': platform,
        'osVersion': osVersion,
        'deviceModel': deviceModel,
        'canRun': canRun,
        'readyNow': readyNow,
        'cameras': [
          for (final c in cameras)
            {'id': c.name, 'direction': c.lensDirection.name},
        ],
        'cameraAuthorization': cameraAuthorization,
        'freeBytes': freeBytes,
        'totalMemoryBytes': totalMemoryBytes,
        'mlKitAvailable': mlKitAvailable,
        'handTrackingAvailable': handTrackingAvailable,
        'usbVideoDevices': usbVideoDevices.length,
        'usbDirectAvailable': usbDirectAvailable,
        'issues': [for (final i in issues) i.toJson()],
        'checkedAt': checkedAt.toUtc().toIso8601String(),
      };

  @override
  String toString() => describe();

  /// Multi-line summary for logs and bug reports.
  String describe() {
    final b = StringBuffer()
      ..writeln('movement_capture support: canRun=$canRun readyNow=$readyNow')
      ..writeln('  $platform ${osVersion ?? '?'} · ${deviceModel ?? '?'}')
      ..writeln(
          '  cameras: ${cameras.map((c) => '${c.name}/${c.lensDirection.name}').join(', ')}')
      ..writeln(
          '  camera access: ${cameraAuthorization ?? '?'} · ML Kit: $mlKitAvailable')
      ..writeln(
          '  free: ${freeBytes ?? '?'} B · RAM: ${totalMemoryBytes ?? '?'} B')
      ..writeln('  usb video devices: ${usbVideoDevices.length} · '
          'direct: ${usbDirectAvailable ? 'yes' : 'no'} · '
          'permission: ${usbVideoDevices.isNotEmpty && usbVideoDevices.every((d) => d.hasPermission) ? 'yes' : 'no'}');
    for (final i in issues) {
      b.writeln('  $i');
    }
    return b.toString();
  }
}

/// Pure decision logic: turns raw facts into a report. No I/O, so it is fully
/// unit-tested. [cameras] is null when listing failed.
SupportReport evaluateSupport({
  required String platform,
  required NativeSupportInfo? native,
  required List<CameraDescription>? cameras,
  required bool mlKitAvailable,
  bool handTrackingAvailable = true,
  List<UsbVideoDevice> usbVideoDevices = const [],
  bool usbDirectAvailable = false,
  UsbProbeResult usbProbe = UsbProbeResult.notRun,
  SupportRequirements requirements = const SupportRequirements(),
  String? nativeError,
  String? cameraError,
  String? mlKitError,
  DateTime? now,
}) {
  final issues = <SupportIssue>[];
  void add(SupportIssueCode c, SupportSeverity s, String m) =>
      issues.add(SupportIssue(c, s, m));

  SupportReport build() => SupportReport(
        platform: platform,
        osVersion: native?.osVersion,
        deviceModel: native?.deviceModel,
        cameras: cameras ?? const [],
        cameraAuthorization: native?.cameraAuthorization,
        freeBytes: native?.freeBytes,
        totalMemoryBytes: native?.totalMemoryBytes,
        mlKitAvailable: mlKitAvailable,
        handTrackingAvailable: handTrackingAvailable,
        usbVideoDevices: usbVideoDevices,
        usbDirectAvailable: usbDirectAvailable,
        issues: List.unmodifiable(issues),
        checkedAt: now ?? DateTime.now(),
      );

  // 1. Platform. Nothing else is meaningful elsewhere.
  if (platform != 'android' && platform != 'ios') {
    add(SupportIssueCode.unsupportedPlatform, SupportSeverity.blocking,
        'movement_capture supports Android and iOS only (this is $platform).');
    return build();
  }
  final isIOS = platform == 'ios';

  // 2. Native info.
  if (native == null) {
    if (isIOS) {
      add(
          SupportIssueCode.checkFailed,
          SupportSeverity.blocking,
          'Native support info unavailable ($nativeError). Cannot confirm '
          'NSCameraUsageDescription; opening the camera could crash the app. '
          'Run `pod install` and rebuild.');
    } else {
      add(
          SupportIssueCode.nativeInfoUnavailable,
          SupportSeverity.warning,
          'Native support info unavailable ($nativeError). OS version, '
          'manifest permission and storage were not checked.');
    }
  } else {
    // 3. OS version.
    if (isIOS) {
      if (!_versionAtLeast(native.osVersion, requirements.minIosVersion)) {
        add(
            SupportIssueCode.osTooOld,
            SupportSeverity.blocking,
            'iOS ${native.osVersion} is older than '
            '${requirements.minIosVersion.join('.')}.');
      }
    } else if (native.sdkInt != null &&
        native.sdkInt! < requirements.minAndroidSdk) {
      add(
          SupportIssueCode.osTooOld,
          SupportSeverity.blocking,
          'Android API ${native.sdkInt} is older than '
          '${requirements.minAndroidSdk}.');
    }

    // 4. Permission declared by the host app.
    if (native.cameraPermissionDeclared == false) {
      add(
        SupportIssueCode.cameraPermissionNotDeclared,
        SupportSeverity.blocking,
        isIOS
            ? 'Info.plist has no NSCameraUsageDescription; iOS would kill the app.'
            : 'AndroidManifest.xml does not declare android.permission.CAMERA.',
      );
    }

    // 5. Access status.
    switch (native.cameraAuthorization) {
      case 'denied':
        add(SupportIssueCode.cameraAccessBlocked, SupportSeverity.userFixable,
            'Camera access was denied. The user can allow it in Settings.');
      case 'restricted':
        add(
            SupportIssueCode.cameraAccessBlocked,
            SupportSeverity.blocking,
            'Camera access is restricted by device policy (parental controls '
            'or MDM). The user cannot change it.');
    }

    // 6. Storage.
    final free = native.freeBytes;
    if (free != null && free < requirements.minFreeBytes) {
      add(SupportIssueCode.lowStorage, SupportSeverity.userFixable,
          'Only $free bytes free; at least ${requirements.minFreeBytes} needed.');
    }

    // 7. Memory and simulator (warnings).
    final ram = native.totalMemoryBytes;
    if (native.isLowRamDevice ||
        (ram != null && ram < requirements.lowMemoryBytes)) {
      add(SupportIssueCode.lowMemoryDevice, SupportSeverity.warning,
          'Low-memory device; live checks may run slowly or be skipped.');
    }
    if (native.isSimulator) {
      add(SupportIssueCode.runningOnSimulator, SupportSeverity.warning,
          'Running on a simulator/emulator; cameras and ML Kit may not work.');
    }
  }

  // 8. Cameras.
  if (cameras == null) {
    add(SupportIssueCode.checkFailed, SupportSeverity.blocking,
        'Could not list cameras ($cameraError).');
  } else if (cameras.isEmpty || native?.hasCameraHardware == false) {
    add(SupportIssueCode.noCamera, SupportSeverity.blocking,
        'No usable camera on this device.');
  } else {
    final usb = cameras
        .where((c) => c.lensDirection == CameraLensDirection.external)
        .length;
    final front = cameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .length;
    if (usb == 0 && usbVideoDevices.isNotEmpty) {
      // Camera2 does not list the webcam; the package may open it directly.
      if (!usbDirectAvailable || usbProbe == UsbProbeResult.failed) {
        add(
          SupportIssueCode.usbDirectUnavailable,
          requirements.requireUsbCamera
              ? SupportSeverity.blocking
              : SupportSeverity.warning,
          'A USB video device is attached but cannot be opened directly '
          '(${usbDirectAvailable ? 'the open probe failed' : 'native library unavailable on this device'}); '
          'a built-in camera will be used.',
        );
      } else {
        add(
          SupportIssueCode.usbDirectInUse,
          SupportSeverity.warning,
          'The USB camera is used directly; this device\'s camera system '
          'doesn\'t list it. Checks work as normal.',
        );
        if (usbVideoDevices.any((d) => !d.hasPermission)) {
          add(
            SupportIssueCode.usbPermissionNeeded,
            SupportSeverity.userFixable,
            'Android has not granted access to the USB camera yet. Call '
            'usbRequestPermission (after the CAMERA permission).',
          );
        }
        if (usbProbe == UsbProbeResult.noFrames) {
          add(
            SupportIssueCode.usbNoFrames,
            SupportSeverity.warning,
            'The USB camera opened but sent no frame within 3 s. This device '
            'may not power the webcam; use a powered hub.',
          );
        }
      }
    } else if (usb == 0) {
      add(
        SupportIssueCode.noUsbCamera,
        requirements.requireUsbCamera
            ? SupportSeverity.blocking
            : SupportSeverity.warning,
        'No USB camera connected; a built-in camera will be used.',
      );
    }
    if (front == 0) {
      add(SupportIssueCode.noFrontCamera, SupportSeverity.warning,
          'No front camera; the fallback will use the back camera.');
    }
  }

  // 9. ML Kit.
  if (!mlKitAvailable) {
    add(SupportIssueCode.mlKitUnavailable, SupportSeverity.blocking,
        'ML Kit pose/face detection failed on this device ($mlKitError).');
  }

  // 9b. Hand tracking (hands step only; not blocking).
  if (!handTrackingAvailable) {
    add(
        SupportIssueCode.handTrackingUnavailable,
        SupportSeverity.warning,
        'MediaPipe hand tracking could not load; the hands step will check '
        'lighting only.');
  }

  return build();
}

/// "17.4.1" >= [15, 5]? Unknown or unparsable versions count as OK (the app's
/// deployment target already enforces the minimum at install time).
bool _versionAtLeast(String? version, List<int> minimum) {
  if (version == null) return true;
  final parts = version.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  for (var i = 0; i < minimum.length; i++) {
    final have = i < parts.length ? parts[i] : 0;
    if (have != minimum[i]) return have > minimum[i];
  }
  return true;
}
