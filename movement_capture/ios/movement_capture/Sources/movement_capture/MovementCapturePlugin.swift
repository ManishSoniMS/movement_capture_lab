import AVFoundation
import Flutter
import UIKit

/// Native helpers for movement_capture: support info, app settings, keep screen on.
public class MovementCapturePlugin: NSObject, FlutterPlugin {
  /// isIdleTimerDisabled before we changed it (nil = we haven't changed it).
  private var previousIdleTimerDisabled: Bool?
  private let hands = HandTracker()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "movement_capture/native", binaryMessenger: registrar.messenger())
    let instance = MovementCapturePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "supportInfo":
      result(supportInfo())
    case "openAppSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(false)
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }
    case "setKeepScreenOn":
      let on = ((call.arguments as? [String: Any])?["on"] as? Bool) ?? false
      setKeepScreenOn(on)
      result(nil)
    case "handTrackingAvailable":
      hands.available(result: result)
    case "detectHands":
      guard let args = call.arguments as? [String: Any],
        let rgba = args["rgba"] as? FlutterStandardTypedData,
        let width = args["width"] as? Int,
        let height = args["height"] as? Int,
        width > 0, height > 0
      else {
        result(FlutterError(code: "BAD_ARGS", message: "rgba/width/height invalid", details: nil))
        return
      }
      hands.detect(rgba: rgba.data, width: width, height: height, result: result)
    case "closeHands":
      hands.close()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func supportInfo() -> [String: Any] {
    let authorization: String
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: authorization = "authorized"
    case .denied: authorization = "denied"
    case .restricted: authorization = "restricted"
    case .notDetermined: authorization = "notDetermined"
    @unknown default: authorization = "notDetermined"
    }

    var freeBytes: Int64 = -1
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    if let values = try? tmp.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let capacity = values.volumeAvailableCapacityForImportantUsage
    {
      freeBytes = capacity
    }

    #if targetEnvironment(simulator)
      let isSimulator = true
    #else
      let isSimulator = false
    #endif

    let usage = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
    let hasCamera = !AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
    ).devices.isEmpty
    let memory = Int64(ProcessInfo.processInfo.physicalMemory)

    return [
      "platform": "ios",
      "osVersion": UIDevice.current.systemVersion,
      "deviceModel": Self.machineIdentifier(),
      "isSimulator": isSimulator,
      "cameraPermissionDeclared": !(usage ?? "").isEmpty,
      "cameraAuthorization": authorization,
      "hasCameraHardware": hasCamera,
      "freeBytes": freeBytes,
      "totalMemoryBytes": memory,
      "isLowRamDevice": memory < 3_000_000_000,
    ]
  }

  /// e.g. "iPad13,16".
  private static func machineIdentifier() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
  }

  private func setKeepScreenOn(_ on: Bool) {
    DispatchQueue.main.async {
      if on {
        if self.previousIdleTimerDisabled == nil {
          self.previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
      } else {
        UIApplication.shared.isIdleTimerDisabled = self.previousIdleTimerDisabled ?? false
        self.previousIdleTimerDisabled = nil
      }
    }
  }
}
