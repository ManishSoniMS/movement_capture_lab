package com.medpredict.movement_capture

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Native helpers for movement_capture: support info, app settings, keep screen on. */
class MovementCapturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var hands: HandTracker
    private var activity: Activity? = null

    /** Whether the window already had KEEP_SCREEN_ON before we set it. */
    private var keepScreenOnWasSet: Boolean? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        hands = HandTracker(context)
        channel = MethodChannel(binding.binaryMessenger, "movement_capture/native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        hands.close()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "supportInfo" -> result.success(supportInfo())
                "openAppSettings" -> result.success(openAppSettings())
                "setKeepScreenOn" -> {
                    setKeepScreenOn(call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "handTrackingAvailable" -> hands.available(result)
                "detectHands" -> {
                    val rgba = call.argument<ByteArray>("rgba")
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    if (rgba == null || width <= 0 || height <= 0 || rgba.size < width * height * 4) {
                        result.error("BAD_ARGS", "rgba/width/height invalid", null)
                    } else {
                        hands.detect(rgba, width, height, result)
                    }
                }
                "closeHands" -> {
                    hands.close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("NATIVE_ERROR", e.toString(), null)
        }
    }

    private fun supportInfo(): Map<String, Any?> {
        val pm = context.packageManager
        val declared = try {
            val info: PackageInfo = if (Build.VERSION.SDK_INT >= 33) {
                pm.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            }
            info.requestedPermissions?.contains(Manifest.permission.CAMERA) == true
        } catch (e: Exception) {
            false
        }
        val granted = context.checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        val freeBytes = try {
            StatFs(context.cacheDir.absolutePath).availableBytes
        } catch (e: Exception) {
            -1L
        }
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }

        return mapOf(
            "platform" to "android",
            "osVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "isSimulator" to isEmulator(),
            "cameraPermissionDeclared" to declared,
            // Android can't tell "never asked" from "denied" without asking.
            "cameraAuthorization" to if (granted) "authorized" else "notDetermined",
            "hasCameraHardware" to pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
            "freeBytes" to freeBytes,
            "totalMemoryBytes" to memory.totalMem,
            "isLowRamDevice" to am.isLowRamDevice,
        )
    }

    private fun isEmulator(): Boolean =
        Build.FINGERPRINT.startsWith("generic") ||
            Build.FINGERPRINT.contains("emulator") ||
            Build.HARDWARE.contains("goldfish") ||
            Build.HARDWARE.contains("ranchu") ||
            Build.PRODUCT.contains("sdk")

    private fun openAppSettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null)
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return true
    }

    private fun setKeepScreenOn(on: Boolean) {
        val window = activity?.window ?: return
        val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (on) {
            if (keepScreenOnWasSet == null) {
                keepScreenOnWasSet = (window.attributes.flags and flag) != 0
            }
            window.addFlags(flag)
        } else {
            // Only clear the flag if we were the ones who set it.
            if (keepScreenOnWasSet == false) window.clearFlags(flag)
            keepScreenOnWasSet = null
        }
    }
}
