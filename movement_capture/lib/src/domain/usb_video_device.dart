/// A USB device that exposes a video-class (0x0E) interface, as reported by
/// the native side. Non-video devices (e.g. an Ethernet chip on the same hub)
/// are never listed.
class UsbVideoDevice {
  const UsbVideoDevice({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.productName,
    this.hasPermission = false,
    this.maxPowerMa,
  });

  /// `/dev/bus/usb/BBB/DDD`. Changes on replug; use [CameraChoice.id] instead.
  final String deviceName;
  final int vendorId;
  final int productId;
  final String productName;
  final bool hasPermission;
  final int? maxPowerMa;

  factory UsbVideoDevice.fromMap(Map<Object?, Object?> m) => UsbVideoDevice(
        deviceName: m['deviceName'] as String? ?? '',
        vendorId: (m['vendorId'] as num?)?.toInt() ?? 0,
        productId: (m['productId'] as num?)?.toInt() ?? 0,
        productName: m['productName'] as String? ?? '',
        hasPermission: m['hasPermission'] as bool? ?? false,
        maxPowerMa: (m['maxPowerMa'] as num?)?.toInt(),
      );
}
