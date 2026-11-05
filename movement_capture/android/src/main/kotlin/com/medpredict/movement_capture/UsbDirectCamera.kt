package com.medpredict.movement_capture

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.graphics.PixelFormat
import android.media.ImageReader
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import androidx.annotation.UiThread
import androidx.annotation.WorkerThread
import com.serenegiant.usb.IFrameCallback
import com.serenegiant.usb.Size
import com.serenegiant.usb.USBMonitor
import com.serenegiant.usb.UVCCamera
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Opens a UVC webcam directly (libuvc) for devices whose Camera2 does not list
 * it, and exposes it to Dart: a preview texture, NV21 frames for analysis and
 * MP4 recording.
 *
 * Adapted from the `uvccamera` Flutter plugin (UvcCameraPlatform.java),
 * Apache-2.0, https://github.com/alexey-pelykh/uvccamera
 *
 * Rules:
 *  - every camera call runs on one [HandlerThread]; results go to Flutter on
 *    the main thread;
 *  - Flutter textures ([PreviewTarget]) are created, resized and released on
 *    the main thread only (`TextureRegistry` is `@UiThread`). The main thread
 *    never waits for the camera thread; the camera thread may wait (1 s) for
 *    the main thread;
 *  - each open gets a session number; callbacks of an older session are dropped;
 *  - nothing here may crash the app: [Throwable] is caught at every entry
 *    (UnsatisfiedLinkError on unsupported ABIs, SecurityException, ...);
 *  - the [USBMonitor] is registered only while a permission request or an open
 *    camera needs it.
 */
class UsbDirectCamera(
    private val context: Context,
    private val textures: TextureRegistry,
    messenger: BinaryMessenger,
) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("movement-capture-usb").apply { start() }
    private val handler = Handler(thread.looper)

    private var frameSink: EventChannel.EventSink? = null
    private var eventSink: EventChannel.EventSink? = null
    private val frameChannel = EventChannel(messenger, "movement_capture/usb_frames")
    private val eventChannel = EventChannel(messenger, "movement_capture/usb_events")

    // ---- state owned by `handler`'s thread (except where marked)
    private var monitor: USBMonitor? = null
    private var camera: UVCCamera? = null
    private var target: PreviewTarget? = null
    private var probeReader: ImageReader? = null
    private var noFrameCheck: Runnable? = null
    private var recorder: MediaRecorder? = null
    private var recordingPath: String? = null
    @Volatile private var openDeviceName: String? = null
    @Volatile private var width = 0
    @Volatile private var height = 0
    private var fps = 30

    private val session = AtomicInteger(0)
    private val frameCount = AtomicInteger(0)
    private val streaming = AtomicBoolean(false)
    private val inFlight = AtomicBoolean(false)
    @Volatile private var analysisIntervalMs = 200L
    @Volatile private var lastSentAt = 0L
    private var frameBuffer: ByteArray? = null

    private var pendingPermission: MethodChannel.Result? = null
    private var pendingPermissionDevice: String? = null
    private var permissionKeepsMonitor = false

    init {
        frameChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { frameSink = sink }
            override fun onCancel(args: Any?) { frameSink = null }
        })
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
            override fun onCancel(args: Any?) { eventSink = null }
        })
    }

    // ------------------------------------------------------------ dispatch

    /** Handles the `usb*` channel methods. Returns false if [method] is not ours. */
    fun handle(method: String, args: Map<*, *>?, result: MethodChannel.Result): Boolean {
        when (method) {
            "usbDirectAvailable" -> reply(result) { libraryAvailable() }
            "usbList" -> reply(result) { list() }
            "usbRequestPermission" -> requestPermission(args?.get("deviceName") as? String, result)
            "usbOpen" -> openOnMain(args, result)
            "usbStartStream" -> onHandler(result) {
                streaming.set(true); inFlight.set(false); ok(result, null)
            }
            "usbStopStream" -> onHandler(result) {
                streaming.set(false); ok(result, null)
            }
            "usbFrameDone" -> { inFlight.set(false); result.success(null) }
            "usbStartRecording" -> onHandler(result) { startRecording(args?.get("path") as? String, result) }
            "usbStopRecording" -> onHandler(result) { stopRecording(result) }
            "usbClose" -> onHandler(result) { closeAll(); ok(result, null) }
            "usbProbe" -> onHandler(result) { probe(args?.get("deviceName") as? String, result) }
            else -> return false
        }
        return true
    }

    /**
     * Main thread. Creates the Flutter preview target here (textures are
     * `@UiThread`), then hands the USB work to the camera thread. Never waits.
     */
    @UiThread
    private fun openOnMain(args: Map<*, *>?, result: MethodChannel.Result) {
        val t = try {
            createTarget(args?.get("previewSurface") == "texture")
        } catch (e: Throwable) {
            Log.w(TAG, "preview target failed", e)
            result.error("open", e.message ?: e.toString(), null)
            return
        }
        val posted = handler.post {
            try {
                open(args, t, result)
            } catch (e: Throwable) {
                Log.w(TAG, "call failed", e)
                fail(result, "usb", e.toString())
            }
        }
        if (!posted) { // camera thread already quit
            t.release()
            result.error("open", "camera thread stopped", null)
        }
    }

    @UiThread
    private fun createTarget(useTexture: Boolean): PreviewTarget {
        check(Looper.myLooper() == Looper.getMainLooper()) { "wrong thread: ${Thread.currentThread().name}" }
        return if (useTexture) {
            val entry = textures.createSurfaceTexture()
            PreviewTarget(entry.id(), entry, null)
        } else {
            val p = textures.createSurfaceProducer()
            PreviewTarget(p.id(), null, p)
        }
    }

    /**
     * A Flutter texture the camera draws into. Every method is main-thread only.
     * Owns the [Surface] it wraps around a SurfaceTexture; a producer's surface
     * belongs to the producer and is never released here.
     */
    private class PreviewTarget(
        val id: Long,
        private val entry: TextureRegistry.SurfaceTextureEntry?,
        private val producer: TextureRegistry.SurfaceProducer?,
    ) {
        private var ownSurface: Surface? = null

        /** Sizes the texture and returns the surface to draw into. */
        @UiThread
        fun resize(w: Int, h: Int): Surface {
            producer?.let { it.setSize(w, h); return it.surface }
            val e = checkNotNull(entry)
            e.surfaceTexture().setDefaultBufferSize(w, h)
            ownSurface?.release()
            return Surface(e.surfaceTexture()).also { ownSurface = it }
        }

        @UiThread
        fun release() {
            try { ownSurface?.release() } catch (_: Throwable) {}
            ownSurface = null
            try { producer?.release() } catch (_: Throwable) {}
            try { entry?.release() } catch (_: Throwable) {}
        }
    }

    /** Releases [t] on the main thread. Call only after the camera stopped drawing. */
    private fun releaseTarget(t: PreviewTarget?) {
        if (t == null) return
        main.post { t.release() }
    }

    /** Camera thread: sizes the target on the main thread and waits up to 1 s. */
    @WorkerThread
    private fun resizeOnMain(t: PreviewTarget, w: Int, h: Int): Surface {
        checkCameraThread()
        val latch = CountDownLatch(1)
        var surface: Surface? = null
        var error: Throwable? = null
        main.post {
            try { surface = t.resize(w, h) } catch (e: Throwable) { error = e }
            latch.countDown()
        }
        if (!latch.await(MAIN_WAIT_MS, TimeUnit.MILLISECONDS)) {
            throw IllegalStateException("main thread did not size the preview in ${MAIN_WAIT_MS} ms")
        }
        error?.let { throw it }
        return surface ?: throw IllegalStateException("preview surface missing")
    }

    private fun checkCameraThread() {
        check(Looper.myLooper() == thread.looper) { "wrong thread: ${Thread.currentThread().name}" }
    }

    private fun reply(result: MethodChannel.Result, block: () -> Any?) {
        try {
            result.success(block())
        } catch (t: Throwable) {
            Log.w(TAG, "call failed", t)
            result.error("usb", t.toString(), null)
        }
    }

    private fun onHandler(result: MethodChannel.Result, block: () -> Unit) {
        handler.post {
            try {
                block()
            } catch (t: Throwable) {
                Log.w(TAG, "call failed", t)
                fail(result, "usb", t.toString())
            }
        }
    }

    private fun ok(result: MethodChannel.Result, value: Any?) = main.post { result.success(value) }
    private fun fail(result: MethodChannel.Result, code: String, msg: String) =
        main.post { result.error(code, msg, null) }

    private fun emit(event: Map<String, Any?>) {
        main.post { try { eventSink?.success(event) } catch (_: Throwable) {} }
    }

    // --------------------------------------------------------------- listing

    /** False when libuvc/libusb cannot load (unsupported ABI). */
    fun libraryAvailable(): Boolean = try {
        Class.forName("com.serenegiant.usb.UVCCamera")
        true
    } catch (t: Throwable) {
        Log.w(TAG, "native library unavailable", t)
        false
    }

    private fun isVideo(d: UsbDevice): Boolean {
        for (i in 0 until d.interfaceCount) {
            if (d.getInterface(i).interfaceClass == UsbConstants.USB_CLASS_VIDEO) return true
        }
        return false
    }

    /** Video-class USB devices only (an Ethernet chip on the same hub is not one). */
    private fun list(): List<Map<String, Any?>> {
        if (!libraryAvailable()) return emptyList()
        val mgr = usbManager ?: return emptyList()
        return mgr.deviceList.values.filter { isVideo(it) }.map { d ->
            mapOf(
                "deviceName" to d.deviceName,
                "vendorId" to d.vendorId,
                "productId" to d.productId,
                "productName" to (d.productName ?: "USB camera"),
                "hasPermission" to mgr.hasPermission(d),
                "maxPowerMa" to try {
                    if (d.configurationCount > 0) d.getConfiguration(0).maxPower * 2 else null
                } catch (_: Throwable) { null },
            )
        }
    }

    private fun find(name: String?): UsbDevice? =
        usbManager?.deviceList?.values?.firstOrNull { it.deviceName == name }

    // ------------------------------------------------------------ permission

    private fun requestPermission(name: String?, result: MethodChannel.Result) {
        handler.post {
            try {
                if (context.checkSelfPermission(Manifest.permission.CAMERA) !=
                    PackageManager.PERMISSION_GRANTED
                ) {
                    // Android denies video-class USB access without CAMERA; do not prompt for USB.
                    ok(result, "cameraPermissionMissing"); return@post
                }
                val device = find(name)
                if (device == null) { ok(result, "denied"); return@post }
                if (usbManager?.hasPermission(device) == true) { ok(result, "granted"); return@post }
                if (pendingPermission != null) { fail(result, "busy", "a request is pending"); return@post }
                pendingPermission = result
                pendingPermissionDevice = device.deviceName
                val m = ensureMonitor()
                if (!m.requestPermission(device)) finishPermission("denied")
            } catch (t: Throwable) {
                Log.w(TAG, "permission request failed", t)
                finishPermission("denied")
            }
        }
    }

    private fun finishPermission(value: String) {
        val r = pendingPermission ?: return
        pendingPermission = null
        pendingPermissionDevice = null
        ok(r, value)
        if (camera == null) stopMonitor()
    }

    // --------------------------------------------------------------- monitor

    private fun ensureMonitor(): USBMonitor {
        monitor?.let { return it }
        val m = USBMonitor(context, object : USBMonitor.OnDeviceConnectListener {
            override fun onAttach(device: UsbDevice) {
                if (isVideo(device)) emit(deviceEvent("attached", device))
            }
            override fun onDettach(device: UsbDevice) {
                emit(deviceEvent("detached", device))
            }
            override fun onConnect(device: UsbDevice, ctrlBlock: USBMonitor.UsbControlBlock, createNew: Boolean) {
                handler.post { if (device.deviceName == pendingPermissionDevice) finishPermission("granted") }
            }
            override fun onDisconnect(device: UsbDevice, ctrlBlock: USBMonitor.UsbControlBlock) {
                if (device.deviceName == openDeviceName) emit(deviceEvent("detached", device))
            }
            override fun onCancel(device: UsbDevice) {
                handler.post { if (device.deviceName == pendingPermissionDevice) finishPermission("denied") }
            }
        })
        m.register()
        monitor = m
        return m
    }

    private fun stopMonitor() {
        val m = monitor ?: return
        monitor = null
        try { m.unregister() } catch (_: Throwable) {}
        try { m.destroy() } catch (_: Throwable) {}
    }

    private fun deviceEvent(type: String, d: UsbDevice) = mapOf(
        "type" to type,
        "deviceName" to d.deviceName,
        "vendorId" to d.vendorId,
        "productId" to d.productId,
    )

    // ------------------------------------------------------------------ open

    @WorkerThread
    private fun open(args: Map<*, *>?, t: PreviewTarget, result: MethodChannel.Result) {
        checkCameraThread()
        closeAll() // one camera at a time (releases the previous target, not t)
        target = t
        val name = args?.get("deviceName") as? String
        val wantW = (args?.get("width") as? Number)?.toInt() ?: 1280
        val wantH = (args?.get("height") as? Number)?.toInt() ?: 720
        analysisIntervalMs = ((args?.get("analysisIntervalMs") as? Number)?.toLong() ?: 200L).coerceAtLeast(0L)
        val info = try {
            openCamera(name, wantW, wantH) { w, h -> resizeOnMain(t, w, h) }
        } catch (e: Throwable) {
            Log.w(TAG, "open failed", e)
            closeAll() // camera first, then the target on the main thread
            val code = if (e is SecurityException) "permission" else "open"
            fail(result, code, e.message ?: e.toString())
            return
        }
        ok(result, info + ("textureId" to t.id))
    }

    /**
     * Opens [name] and starts the preview into the surface [surfaceFor] returns
     * for the chosen mode. Throws on failure; caller cleans up.
     */
    @WorkerThread
    private fun openCamera(
        name: String?,
        wantW: Int,
        wantH: Int,
        surfaceFor: (Int, Int) -> Surface,
    ): Map<String, Any?> {
        checkCameraThread()
        val device = find(name) ?: throw IllegalStateException("USB device not found: $name")
        val my = session.incrementAndGet()
        val m = ensureMonitor()
        val ctrl = m.openDevice(device)
        val cam = UVCCamera()
        camera = cam
        openDeviceName = device.deviceName
        cam.open(ctrl)

        val sizes: List<Size> = cam.supportedSizeList ?: emptyList()
        val modes = sizes.map { "${it.width}x${it.height} ${formatName(it.type)}" }
        // MJPEG closest to the requested area, else YUYV closest, else fail.
        val chosen = closest(sizes.filter { it.type == TYPE_MJPEG }, wantW, wantH)?.let { it to UVCCamera.FRAME_FORMAT_MJPEG }
            ?: closest(sizes.filter { it.type == TYPE_YUYV }, wantW, wantH)?.let { it to UVCCamera.FRAME_FORMAT_YUYV }
            ?: throw IllegalStateException("No usable mode. Offered: ${modes.joinToString()}")
        val (size, frameFormat) = chosen
        cam.setPreviewSize(size.width, size.height, frameFormat)
        width = size.width
        height = size.height
        fps = size.fps?.maxOrNull()?.toInt()?.takeIf { it in 5..60 } ?: 30

        val surface = surfaceFor(width, height)

        frameCount.set(0)
        frameBuffer = null
        inFlight.set(false)
        lastSentAt = 0L
        cam.setFrameCallback(IFrameCallback { buf -> onNativeFrame(my, buf) }, UVCCamera.PIXEL_FORMAT_NV21)
        cam.setPreviewDisplay(surface)
        cam.startPreview()
        val startedAt = SystemClock.elapsedRealtime()
        val check = Runnable {
            if (session.get() == my && camera != null && frameCount.get() == 0) {
                Log.w(TAG, "no frame within 3 s of startPreview")
                emit(mapOf("type" to "noFrames", "afterMs" to SystemClock.elapsedRealtime() - startedAt))
            }
        }
        noFrameCheck = check
        handler.postDelayed(check, NO_FRAME_MS)

        return mapOf(
            "width" to width,
            "height" to height,
            "format" to formatName(if (frameFormat == UVCCamera.FRAME_FORMAT_MJPEG) TYPE_MJPEG else TYPE_YUYV),
            "fps" to fps,
            "modes" to modes,
        )
    }

    private fun closest(list: List<Size>, w: Int, h: Int): Size? {
        val want = w.toLong() * h.toLong()
        return list.minByOrNull { Math.abs(it.width.toLong() * it.height.toLong() - want) }
    }

    private fun formatName(type: Int) = when (type) {
        TYPE_MJPEG -> "mjpeg"
        TYPE_YUYV -> "yuyv"
        else -> "type$type"
    }

    // ---------------------------------------------------------------- frames

    /** Native thread. At most one frame in flight; never faster than the analysis interval. */
    private fun onNativeFrame(my: Int, buf: ByteBuffer) {
        if (session.get() != my) return
        frameCount.incrementAndGet()
        if (!streaming.get()) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastSentAt < analysisIntervalMs) return
        if (!inFlight.compareAndSet(false, true)) return
        try {
            val n = buf.remaining()
            var bytes = frameBuffer
            if (bytes == null || bytes.size != n) {
                bytes = ByteArray(n)
                frameBuffer = bytes
            }
            buf.get(bytes)
            lastSentAt = now
            val w = width
            val h = height
            val out = bytes
            main.post {
                if (session.get() != my) { inFlight.set(false); return@post }
                val sink = frameSink
                if (sink == null) { inFlight.set(false); return@post }
                try {
                    sink.success(mapOf("bytes" to out, "width" to w, "height" to h, "tMs" to now))
                } catch (t: Throwable) {
                    inFlight.set(false)
                }
            }
        } catch (t: Throwable) {
            inFlight.set(false)
            Log.w(TAG, "frame copy failed", t)
        }
    }

    // ------------------------------------------------------------- recording

    private fun bitrate(): Int {
        val scale = (width.toLong() * height.toLong()).toDouble() / (1280.0 * 720.0)
        return (6_000_000 * scale).toInt().coerceIn(2_000_000, 24_000_000)
    }

    @Suppress("DEPRECATION")
    private fun newRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()

    @WorkerThread
    private fun startRecording(path: String?, result: MethodChannel.Result) {
        checkCameraThread()
        val cam = camera ?: throw IllegalStateException("camera not open")
        if (path.isNullOrEmpty()) throw IllegalArgumentException("path missing")
        if (recorder != null) throw IllegalStateException("already recording")
        File(path).parentFile?.mkdirs()
        val r = newRecorder()
        try {
            r.setVideoSource(MediaRecorder.VideoSource.SURFACE) // no audio source: no audio track
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            r.setVideoSize(width, height)
            r.setVideoFrameRate(fps)
            r.setVideoEncodingBitRate(bitrate())
            r.setOutputFile(path)
            r.prepare()
            cam.startCapture(r.surface)
            r.start()
        } catch (t: Throwable) {
            try { r.reset() } catch (_: Throwable) {}
            try { r.release() } catch (_: Throwable) {}
            File(path).delete()
            throw t
        }
        recorder = r
        recordingPath = path
        ok(result, path)
    }

    @WorkerThread
    private fun stopRecording(result: MethodChannel.Result) {
        checkCameraThread()
        val r = recorder ?: throw IllegalStateException("not recording")
        val path = recordingPath
        recorder = null
        recordingPath = null
        try { camera?.stopCapture() } catch (t: Throwable) { Log.w(TAG, "stopCapture", t) }
        try {
            r.stop()
        } catch (t: Throwable) {
            // Stopped too early: the file is unusable.
            try { r.release() } catch (_: Throwable) {}
            if (path != null) File(path).delete()
            throw t
        }
        try { r.reset() } catch (_: Throwable) {}
        try { r.release() } catch (_: Throwable) {}
        ok(result, path)
    }

    // ----------------------------------------------------------------- probe

    /**
     * Opens, waits up to 3 s for a frame, closes. "ok" | "noFrames" | "failed".
     * No Flutter texture: frames go to the frame callback and the preview is
     * drawn into a private [ImageReader] that discards them (the native
     * preview thread wants a display surface; whether it also runs without
     * one is unverified).
     */
    @WorkerThread
    private fun probe(name: String?, result: MethodChannel.Result) {
        checkCameraThread()
        if (camera != null) { ok(result, "failed"); return }
        try {
            openCamera(name, 640, 480) { w, h ->
                val reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
                reader.setOnImageAvailableListener({ r ->
                    try { r.acquireLatestImage()?.close() } catch (_: Throwable) {}
                }, handler)
                probeReader = reader
                reader.surface
            }
        } catch (e: Throwable) {
            Log.w(TAG, "probe open failed", e)
            closeAll()
            ok(result, "failed")
            return
        }
        val my = session.get()
        handler.postDelayed({
            if (session.get() != my) { ok(result, "failed"); return@postDelayed } // superseded
            val got = frameCount.get() > 0
            closeAll()
            ok(result, if (got) "ok" else "noFrames")
        }, NO_FRAME_MS + 200)
    }

    // ----------------------------------------------------------------- close

    /**
     * Stops everything in this order: recorder, frame callback, preview, camera,
     * probe sink, then the Flutter texture (released on the main thread, after
     * the native preview thread can no longer write to it). Safe twice.
     */
    @WorkerThread
    private fun closeAll() {
        checkCameraThread()
        session.incrementAndGet() // drops callbacks of the old session
        streaming.set(false)
        inFlight.set(false)
        noFrameCheck?.let { handler.removeCallbacks(it) }
        noFrameCheck = null
        recorder?.let { r ->
            try { camera?.stopCapture() } catch (_: Throwable) {}
            try { r.stop() } catch (_: Throwable) {}
            try { r.reset() } catch (_: Throwable) {}
            try { r.release() } catch (_: Throwable) {}
            recordingPath?.let { File(it).delete() } // an unfinished clip is never kept
        }
        recorder = null
        recordingPath = null
        try { camera?.setFrameCallback(null, 0) } catch (_: Throwable) {}
        camera?.let { c ->
            try { c.stopPreview() } catch (_: Throwable) {}
            try { c.close() } catch (_: Throwable) {}
            try { c.destroy() } catch (_: Throwable) {}
        }
        camera = null
        try { probeReader?.close() } catch (_: Throwable) {}
        probeReader = null
        val old = target
        target = null
        releaseTarget(old)
        openDeviceName = null
        frameBuffer = null
        if (pendingPermission == null) stopMonitor()
    }

    /** Engine detached or activity destroyed: release everything. */
    fun release() {
        handler.post {
            try { closeAll() } catch (_: Throwable) {}
            pendingPermission?.let { ok(it, "denied") }
            pendingPermission = null
            stopMonitor()
        }
        frameChannel.setStreamHandler(null)
        eventChannel.setStreamHandler(null)
        thread.quitSafely()
    }

    /** Activity went away (not a config change): free the camera and monitor. */
    fun onActivityGone() {
        handler.post {
            try { closeAll() } catch (_: Throwable) {}
            stopMonitor()
        }
    }

    private companion object {
        const val TAG = "UsbDirectCamera"
        const val TYPE_YUYV = 4 // UVC_VS_FORMAT_UNCOMPRESSED
        const val TYPE_MJPEG = 6 // UVC_VS_FORMAT_MJPEG
        const val NO_FRAME_MS = 3000L
        const val MAIN_WAIT_MS = 1000L
    }
}
