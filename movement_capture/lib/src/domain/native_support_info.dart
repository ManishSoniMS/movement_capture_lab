/// Raw answers from the plugin's native side. Every field is optional because
/// older builds or unexpected platforms may not provide it.
class NativeSupportInfo {
  const NativeSupportInfo({
    this.platform,
    this.osVersion,
    this.sdkInt,
    this.deviceModel,
    this.isSimulator = false,
    this.cameraPermissionDeclared,
    this.cameraAuthorization,
    this.hasCameraHardware,
    this.freeBytes,
    this.totalMemoryBytes,
    this.isLowRamDevice = false,
  });

  factory NativeSupportInfo.fromMap(Map<Object?, Object?> m) {
    int? asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
    final free = asInt(m['freeBytes']);
    final memory = asInt(m['totalMemoryBytes']);
    return NativeSupportInfo(
      platform: m['platform'] as String?,
      osVersion: m['osVersion'] as String?,
      sdkInt: asInt(m['sdkInt']),
      deviceModel: m['deviceModel'] as String?,
      isSimulator: m['isSimulator'] == true,
      cameraPermissionDeclared: m['cameraPermissionDeclared'] as bool?,
      cameraAuthorization: m['cameraAuthorization'] as String?,
      hasCameraHardware: m['hasCameraHardware'] as bool?,
      freeBytes: (free == null || free < 0) ? null : free,
      totalMemoryBytes: (memory == null || memory <= 0) ? null : memory,
      isLowRamDevice: m['isLowRamDevice'] == true,
    );
  }

  final String? platform;
  final String? osVersion;
  final int? sdkInt;
  final String? deviceModel;
  final bool isSimulator;
  final bool? cameraPermissionDeclared;

  /// "authorized", "denied", "restricted" or "notDetermined".
  final String? cameraAuthorization;
  final bool? hasCameraHardware;
  final int? freeBytes;
  final int? totalMemoryBytes;
  final bool isLowRamDevice;
}
