package com.medpredict.movement_capture_lab

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbManager
import android.Manifest
import android.os.Build
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
                        "usbVideoDevices" -> result.success(
                            usbDevices().filter { it["isVideo"] == true }
                        )
                        "usbDevices" -> result.success(usbDevices())
                        "usbHasPermission" -> {
                            val name = call.argument<String>("deviceName")
                            val usb = getSystemService(Context.USB_SERVICE) as UsbManager
                            val device = usb.deviceList[name]
                            result.success(device != null && usb.hasPermission(device))
                        }
                        "cameraPermissionGranted" -> result.success(cameraGranted())
                        "requestCameraPermission" -> requestCameraPermission(result)
                        "impellerEnabled" -> result.success(impellerEnabled())
                        "nativeLog" -> readNativeLog(result)
                        "clearNativeLog" -> clearNativeLog(result)
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

    private fun cameraGranted(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private var pendingCameraResult: MethodChannel.Result? = null

    /** Asks for the CAMERA runtime permission; Android 9+ needs it before USB video access. */
    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (cameraGranted()) {
            result.success(true)
            return
        }
        if (pendingCameraResult != null) {
            result.error("PENDING", "A CAMERA request is already pending", null)
            return
        }
        pendingCameraResult = result
        requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingCameraResult?.success(granted)
            pendingCameraResult = null
        }
    }

    /** Every attached USB device; `isVideo` marks the ones with a video-class interface. */
    private fun usbDevices(): List<Map<String, Any?>> {
        val usb = getSystemService(Context.USB_SERVICE) as UsbManager
        return usb.deviceList.values.map { d ->
            val interfaces = (0 until d.interfaceCount).map {
                val i = d.getInterface(it)
                "%02X/%02X".format(i.interfaceClass, i.interfaceSubclass)
            }
            val isVideo = d.deviceClass == UsbConstants.USB_CLASS_VIDEO ||
                (0 until d.interfaceCount).any {
                    d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_VIDEO
                }
            val maxPower = if (d.configurationCount > 0) d.getConfiguration(0).maxPower else -1
            mapOf(
                "deviceName" to d.deviceName,
                "name" to (d.productName ?: d.deviceName),
                "vendorId" to d.vendorId,
                "productId" to d.productId,
                "isVideo" to isVideo,
                "interfaces" to interfaces,
                "maxPowerMa" to maxPower,
                "hasPermission" to usb.hasPermission(d),
            )
        }
    }

    /**
     * The `EnableImpeller` value baked into this build's manifest (lab build
     * switch `-PlabImpeller=false`). `null` in the answer means "not set", which
     * Flutter treats as the default (on).
     */
    private fun impellerEnabled(): Boolean? {
        val info = packageManager.getApplicationInfo(
            packageName,
            PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
        )
        val md = info.metaData ?: return null
        val key = "io.flutter.embedding.android.EnableImpeller"
        if (!md.containsKey(key)) return null
        return when (val v = md.get(key)) {
            is Boolean -> v
            is String -> v.toBoolean()
            else -> null
        }
    }

    /** Runs a short command off the main thread and returns its output lines. */
    private fun runLogcat(vararg args: String): Pair<Int, List<String>> {
        val proc = ProcessBuilder(listOf("logcat") + args).redirectErrorStream(true).start()
        val lines = proc.inputStream.bufferedReader().readLines()
        return proc.waitFor() to lines
    }

    /**
     * Last 200 lines of this app's own log that mention the USB camera stack.
     * An app may read its own process log without READ_LOGS.
     */
    private fun readNativeLog(result: MethodChannel.Result) {
        Thread {
            try {
                val (code, lines) = runLogcat("-d", "-v", "time", "--pid=${android.os.Process.myPid()}")
                val keep = Regex(
                    "UVCCamera|USBMonitor|libuvc|libusb|UvcCamera|ANativeWindow|uvc_|" +
                        "ImageReader|SurfaceProducer|BufferQueue",
                )
                val out = lines.filter { keep.containsMatchIn(it) }.takeLast(200)
                runOnUiThread {
                    result.success(
                        mapOf("exit" to code, "total" to lines.size, "lines" to out),
                    )
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("LOGCAT_FAILED", e.toString(), null) }
            }
        }.start()
    }

    /** `logcat -c`. Android may refuse it for a normal app; the exit code says. */
    private fun clearNativeLog(result: MethodChannel.Result) {
        Thread {
            try {
                val (code, lines) = runLogcat("-c")
                runOnUiThread { result.success(mapOf("exit" to code, "output" to lines)) }
            } catch (e: Exception) {
                runOnUiThread { result.error("LOGCAT_FAILED", e.toString(), null) }
            }
        }.start()
    }

    companion object {
        private const val CHANNEL = "lab/camera_diagnostics"
        private const val CAMERA_REQUEST = 4711
    }
}
