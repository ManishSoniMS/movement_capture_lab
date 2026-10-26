package com.medpredict.movement_capture

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/** MediaPipe Hand Landmarker for the hands step. All work runs off the main thread. */
class HandTracker(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var landmarker: HandLandmarker? = null
    private var lastTimestamp = 0L

    private fun create(): HandLandmarker {
        // Load the model into a direct buffer: works whether or not the asset
        // was compressed when the app was packaged.
        val bytes = context.assets.open(MODEL).use { it.readBytes() }
        val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        buffer.put(bytes).rewind()
        val options = HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(buffer).build())
            .setRunningMode(RunningMode.VIDEO)
            .setNumHands(2)
            .setMinHandDetectionConfidence(0.5f)
            .setMinHandPresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        return HandLandmarker.createFromOptions(context, options)
    }

    fun available(result: MethodChannel.Result) {
        executor.execute {
            val ok = try {
                (landmarker ?: create().also { landmarker = it })
                true
            } catch (e: Throwable) {
                false
            }
            main.post { result.success(ok) }
        }
    }

    /** [rgba] is width × height × 4 bytes, upright, R G B A order. */
    fun detect(rgba: ByteArray, width: Int, height: Int, result: MethodChannel.Result) {
        executor.execute {
            try {
                val lm = landmarker ?: create().also { landmarker = it }
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba)) // ARGB_8888 memory = RGBA
                // VIDEO mode needs strictly increasing timestamps.
                val ts = maxOf(lastTimestamp + 1, SystemClock.uptimeMillis())
                lastTimestamp = ts
                val out = lm.detectForVideo(BitmapImageBuilder(bitmap).build(), ts)
                val hands = out.landmarks().mapIndexed { i, points ->
                    val category = out.handedness().getOrNull(i)?.firstOrNull()
                    mapOf(
                        "handedness" to (category?.categoryName() ?: "Unknown"),
                        "score" to (category?.score()?.toDouble() ?: 0.0),
                        "points" to points.flatMap {
                            listOf(it.x().toDouble(), it.y().toDouble(), it.z().toDouble())
                        },
                    )
                }
                bitmap.recycle()
                main.post { result.success(hands) }
            } catch (e: Throwable) {
                main.post { result.error("HAND_TRACKING_FAILED", e.toString(), null) }
            }
        }
    }

    fun close() {
        executor.execute {
            try {
                landmarker?.close()
            } catch (_: Throwable) {
            }
            landmarker = null
            lastTimestamp = 0L
        }
    }

    companion object {
        private const val MODEL = "hand_landmarker.task"
    }
}
