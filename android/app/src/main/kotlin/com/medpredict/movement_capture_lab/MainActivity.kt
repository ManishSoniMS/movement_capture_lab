package com.medpredict.movement_capture_lab

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * LAB ONLY: asks Android directly which cameras and USB video devices exist,
 * so the lab can compare that with what the Flutter plugin reports.
 * Never copy this into the kiosk app.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "camera2Cameras" -> result.success(camera2Cameras())
                        "usbVideoDevices" -> result.success(usbVideoDevices())
                        "hasExternalCameraFeature" -> result.success(
                            packageManager.hasSystemFeature(
                                PackageManager.FEATURE_CAMERA_EXTERNAL
                            )
                        )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("DIAGNOSTICS_FAILED", e.toString(), null)
                }
            }
    }

    private fun camera2Cameras(): List<Map<String, Any?>> {
        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        return manager.cameraIdList.map { id ->
            val ch = manager.getCameraCharacteristics(id)
            val facing = when (ch.get(CameraCharacteristics.LENS_FACING)) {
                CameraMetadata.LENS_FACING_FRONT -> "front"
                CameraMetadata.LENS_FACING_BACK -> "back"
                CameraMetadata.LENS_FACING_EXTERNAL -> "external"
                else -> "unknown"
            }
            val level = when (ch.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)) {
                CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "legacy"
                CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "limited"
                CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "full"
                CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "level3"
                CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> "external"
                else -> "unknown"
            }
            val caps = ch.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)
            mapOf(
                "id" to id,
                "facing" to facing,
                "numericId" to ((id.toIntOrNull() ?: -1) >= 0),
                "backwardCompatible" to caps.contains(
                    CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE
                ),
                "hardwareLevel" to level,
                "sensorOrientation" to (ch.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0),
            )
        }
    }

    private fun usbVideoDevices(): List<Map<String, Any?>> {
        val usb = getSystemService(Context.USB_SERVICE) as UsbManager
        return usb.deviceList.values
            .filter { d ->
                d.deviceClass == UsbConstants.USB_CLASS_VIDEO ||
                    (0 until d.interfaceCount).any {
                        d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_VIDEO
                    }
            }
            .map { d ->
                mapOf(
                    "name" to (d.productName ?: d.deviceName),
                    "vendorId" to d.vendorId,
                    "productId" to d.productId,
                )
            }
    }

    companion object {
        private const val CHANNEL = "lab/camera_diagnostics"
    }
}
