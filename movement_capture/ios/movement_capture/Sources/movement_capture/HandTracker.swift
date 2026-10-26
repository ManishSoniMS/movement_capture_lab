import Flutter
import MediaPipeTasksVision
import UIKit

/// MediaPipe Hand Landmarker for the hands step. All work runs off the main thread.
final class HandTracker {
  private let queue = DispatchQueue(label: "movement_capture.hands")
  private var landmarker: HandLandmarker?
  private var lastTimestamp = 0

  private func create() throws -> HandLandmarker {
    guard let path = HandTracker.modelPath() else {
      throw NSError(
        domain: "movement_capture", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "hand_landmarker.task not found"])
    }
    let options = HandLandmarkerOptions()
    options.baseOptions.modelAssetPath = path
    options.runningMode = .video
    options.numHands = 2
    options.minHandDetectionConfidence = 0.5
    options.minHandPresenceConfidence = 0.5
    options.minTrackingConfidence = 0.5
    return try HandLandmarker(options: options)
  }

  private static func modelPath() -> String? {
    let bundle = Bundle(for: HandTracker.self)
    if let url = bundle.url(forResource: "movement_capture_models", withExtension: "bundle"),
      let models = Bundle(url: url),
      let path = models.path(forResource: "hand_landmarker", ofType: "task")
    {
      return path
    }
    return bundle.path(forResource: "hand_landmarker", ofType: "task")
  }

  func available(result: @escaping FlutterResult) {
    queue.async {
      var ok = false
      do {
        if self.landmarker == nil { self.landmarker = try self.create() }
        ok = true
      } catch {
        ok = false
      }
      DispatchQueue.main.async { result(ok) }
    }
  }

  /// [rgba] is width × height × 4 bytes, upright, R G B A order.
  func detect(rgba: Data, width: Int, height: Int, result: @escaping FlutterResult) {
    queue.async {
      do {
        if self.landmarker == nil { self.landmarker = try self.create() }
        guard let landmarker = self.landmarker,
          let image = HandTracker.uiImage(rgba: rgba, width: width, height: height)
        else {
          throw NSError(
            domain: "movement_capture", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "could not build image"])
        }
        let mpImage = try MPImage(uiImage: image)
        // VIDEO mode needs strictly increasing timestamps.
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        let ts = max(self.lastTimestamp + 1, now)
        self.lastTimestamp = ts
        let out = try landmarker.detect(videoFrame: mpImage, timestampInMilliseconds: ts)
        var hands: [[String: Any]] = []
        for (i, points) in out.landmarks.enumerated() {
          let category = i < out.handedness.count ? out.handedness[i].first : nil
          var flat: [Double] = []
          flat.reserveCapacity(points.count * 3)
          for p in points {
            flat.append(Double(p.x))
            flat.append(Double(p.y))
            flat.append(Double(p.z))
          }
          hands.append([
            "handedness": category?.categoryName ?? "Unknown",
            "score": Double(category?.score ?? 0),
            "points": flat,
          ])
        }
        DispatchQueue.main.async { result(hands) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "HAND_TRACKING_FAILED", message: "\(error)", details: nil))
        }
      }
    }
  }

  func close() {
    queue.async {
      self.landmarker = nil
      self.lastTimestamp = 0
    }
  }

  private static func uiImage(rgba: Data, width: Int, height: Int) -> UIImage? {
    guard rgba.count >= width * height * 4,
      let provider = CGDataProvider(data: rgba as CFData),
      let cgImage = CGImage(
        width: width, height: height,
        bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent)
    else { return nil }
    return UIImage(cgImage: cgImage)
  }
}
