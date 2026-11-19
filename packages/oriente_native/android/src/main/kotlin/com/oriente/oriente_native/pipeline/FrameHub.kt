package com.oriente.oriente_native.pipeline

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.LifecycleOwner
import com.oriente.oriente_native.camera.CameraModule
import com.oriente.oriente_native.ocr.OcrModule
import com.oriente.oriente_native.vision.CableDetectorModule
import com.oriente.oriente_native.vision.DetectionMerger
import com.oriente.oriente_native.vision.VisionModule
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Single CameraX analysis session → shared FrameContext → N consumers.
 * Drops frames when busy; never blocks the camera thread.
 */
class FrameHub(
    private val context: Context,
    private val camera: CameraModule,
    private val vision: VisionModule,
    private val ocr: OcrModule,
    private val cableDetector: CableDetectorModule? = null,
) {
    private val main = Handler(Looper.getMainLooper())
    private val workers = Executors.newFixedThreadPool(2)
    private val consumers = CopyOnWriteArrayList<FrameConsumer>()
    private val running = AtomicBoolean(false)
    private val analyzing = AtomicBoolean(false)
    private val ocrBusy = AtomicBoolean(false)
    private var lastOcrAt = 0L
    private var ocrIntervalMs = 300L
    private var lastCableAt = 0L
    private var cableIntervalMs = 700L
    private var lastCableDetections = emptyList<com.oriente.oriente_native.vision.DetectedObject>()
    private var lastLuma: Float? = null
    private var lastFlowGrid: FloatArray? = null
    private var frameCount = AtomicLong(0)
    private var fpsWindowStart = System.currentTimeMillis()
    private var fps = 0.0
    @Volatile var lastContext: FrameContext? = null
        private set
    @Volatile var lastJpeg: ByteArray? = null
        private set
    @Volatile var lastMemoryMb: Double = 0.0
        private set
    @Volatile var perfOverlay = false
    var onFrameBroadcast: ((FrameContext) -> Unit)? = null
    @Volatile private var keepJpeg = true
    @Volatile private var jpegMaxEdge = 1024
    @Volatile private var jpegQuality = 75

    fun addConsumer(c: FrameConsumer) {
        if (consumers.none { it.id == c.id }) {
            consumers.add(c)
            c.start()
        }
        ensureStarted()
    }

    fun removeConsumer(id: String) {
        val doomed = consumers.filter { it.id == id }
        consumers.removeAll { it.id == id }
        doomed.forEach { it.stop() }
        if (consumers.isEmpty()) stop()
    }

    fun clearConsumers() {
        consumers.forEach { it.stop() }
        consumers.clear()
        stop()
    }

    fun setOcrIntervalMs(ms: Long) {
        ocrIntervalMs = ms.coerceIn(200, 1000)
    }

    private var lifecycleOwner: LifecycleOwner? = null

    fun bindLifecycle(owner: LifecycleOwner) {
        lifecycleOwner = owner
        if (consumers.isNotEmpty()) ensureStarted()
    }

    private fun ensureStarted() {
        val owner = lifecycleOwner ?: return
        if (running.get()) return
        if (!vision.isReady) vision.init()
        running.set(true)
        camera.start(
            lifecycleOwner = owner,
            onFrame = { bmp -> workers.execute { analyze(bmp) } },
            onError = { /* swallow; consumers keep last context */ },
        )
    }

    fun stop() {
        if (!running.getAndSet(false)) return
        camera.stop()
    }

    private fun analyze(bitmap: Bitmap) {
        if (!analyzing.compareAndSet(false, true)) {
            bitmap.recycle()
            return
        }
        try {
            val t0 = System.currentTimeMillis()
            val sharpness = estimateSharpness(bitmap)
            val brightness = estimateBrightness(bitmap)
            val flowMotion = estimateOpticalFlow(bitmap)
            val lumaMotion = estimateMotion(brightness)
            val poseMotion = estimatePoseMotion(bitmap)
            val motion = max(flowMotion, max(lumaMotion, poseMotion))
            val primary = if (vision.isReady) vision.detect(bitmap) else emptyList()
            val nowCable = System.currentTimeMillis()
            if (cableDetector?.isReady == true &&
                nowCable - lastCableAt >= cableIntervalMs
            ) {
                lastCableAt = nowCable
                lastCableDetections = cableDetector.detect(bitmap)
            }
            val detections = DetectionMerger.merge(primary, lastCableDetections)
            val detectMs = System.currentTimeMillis() - t0

            var ocrBoxes = lastContext?.ocrBoxes.orEmpty()
            var ocrText = lastContext?.ocrFullText.orEmpty()
            var ocrMs = 0L
            val now = System.currentTimeMillis()
            if (now - lastOcrAt >= ocrIntervalMs && ocrBusy.compareAndSet(false, true)) {
                lastOcrAt = now
                try {
                    val t1 = System.currentTimeMillis()
                    val frame = ocr.recognizeBitmap(bitmap, "", 0)
                    ocrBoxes = frame.boxes
                    ocrText = frame.fullText
                    ocrMs = System.currentTimeMillis() - t1
                } finally {
                    ocrBusy.set(false)
                }
            }

            if (keepJpeg) {
                lastJpeg = encodeJpeg(bitmap, jpegMaxEdge, jpegQuality)
            }
            val rt = Runtime.getRuntime()
            lastMemoryMb =
                (rt.totalMemory() - rt.freeMemory()).toDouble() / (1024.0 * 1024.0)

            tickFps()
            val ctx = FrameContext(
                timestampMs = now,
                rotationDegrees = 0,
                sharpness = sharpness,
                brightness = brightness,
                motionScore = motion,
                detections = detections,
                ocrBoxes = ocrBoxes,
                ocrFullText = ocrText,
                width = bitmap.width,
                height = bitmap.height,
                fps = fps,
                detectLatencyMs = detectMs,
                ocrLatencyMs = ocrMs,
            )
            lastContext = ctx
            for (c in consumers) {
                try {
                    c.onFrame(ctx)
                } catch (_: Throwable) {
                }
            }
            val broadcast = onFrameBroadcast
            if (broadcast != null) {
                main.post { broadcast(ctx) }
            }
        } finally {
            analyzing.set(false)
            bitmap.recycle()
        }
    }

    fun grabJpeg(maxEdge: Int = 1024, quality: Int = 75): ByteArray? {
        jpegMaxEdge = maxEdge.coerceIn(256, 2048)
        jpegQuality = quality.coerceIn(40, 95)
        return lastJpeg
    }

    fun setJpegCapture(enabled: Boolean, maxEdge: Int = 1024, quality: Int = 75) {
        keepJpeg = enabled
        jpegMaxEdge = maxEdge.coerceIn(256, 2048)
        jpegQuality = quality.coerceIn(40, 95)
    }

    private fun encodeJpeg(src: Bitmap, maxEdge: Int, quality: Int): ByteArray {
        val longEdge = max(src.width, src.height)
        val scaled = if (longEdge > maxEdge) {
            val scale = maxEdge.toFloat() / longEdge
            Bitmap.createScaledBitmap(
                src,
                max(1, (src.width * scale).toInt()),
                max(1, (src.height * scale).toInt()),
                true,
            )
        } else {
            src
        }
        val bos = java.io.ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, quality, bos)
        if (scaled !== src) scaled.recycle()
        return bos.toByteArray()
    }

    private fun tickFps() {
        frameCount.incrementAndGet()
        val now = System.currentTimeMillis()
        val dt = now - fpsWindowStart
        if (dt >= 1000) {
            fps = frameCount.get() * 1000.0 / max(1, dt)
            frameCount.set(0)
            fpsWindowStart = now
        }
    }

    private fun estimateBrightness(bmp: Bitmap): Float {
        val step = max(8, min(bmp.width, bmp.height) / 40)
        var sum = 0L
        var n = 0
        var y = 0
        while (y < bmp.height) {
            var x = 0
            while (x < bmp.width) {
                val c = bmp.getPixel(x, y)
                val r = (c shr 16) and 0xff
                val g = (c shr 8) and 0xff
                val b = c and 0xff
                sum += (r * 3 + g * 4 + b) / 8
                n++
                x += step
            }
            y += step
        }
        return if (n == 0) 0.5f else (sum.toFloat() / n) / 255f
    }

    private fun estimateSharpness(bmp: Bitmap): Float {
        // Laplacian-ish on downsampled luma
        val w = min(64, bmp.width)
        val h = min(64, bmp.height)
        if (w < 3 || h < 3) return 0f
        val scaled = Bitmap.createScaledBitmap(bmp, w, h, true)
        var acc = 0.0
        var n = 0
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val c = luma(scaled.getPixel(x, y))
                val lap = abs(
                    4 * c -
                        luma(scaled.getPixel(x - 1, y)) -
                        luma(scaled.getPixel(x + 1, y)) -
                        luma(scaled.getPixel(x, y - 1)) -
                        luma(scaled.getPixel(x, y + 1)),
                )
                acc += lap
                n++
            }
        }
        if (scaled !== bmp) scaled.recycle()
        return if (n == 0) 0f else (acc / n).toFloat()
    }

    private fun luma(c: Int): Int {
        val r = (c shr 16) and 0xff
        val g = (c shr 8) and 0xff
        val b = c and 0xff
        return (r * 3 + g * 4 + b) / 8
    }

    private fun estimateMotion(brightness: Float): Float {
        val prev = lastLuma
        lastLuma = brightness
        if (prev == null) return 0f
        return abs(brightness - prev) * 8f
    }

    /** Coarse block optical flow on a 8x8 luma grid. */
    private fun estimateOpticalFlow(bmp: Bitmap): Float {
        val gw = 8
        val gh = 8
        val grid = FloatArray(gw * gh)
        val cellW = max(1, bmp.width / gw)
        val cellH = max(1, bmp.height / gh)
        for (gy in 0 until gh) {
            for (gx in 0 until gw) {
                var sum = 0L
                var n = 0
                val x0 = gx * cellW
                val y0 = gy * cellH
                var y = y0
                while (y < min(bmp.height, y0 + cellH)) {
                    var x = x0
                    while (x < min(bmp.width, x0 + cellW)) {
                        sum += luma(bmp.getPixel(x, y))
                        n++
                        x += max(2, cellW / 4)
                    }
                    y += max(2, cellH / 4)
                }
                grid[gy * gw + gx] = if (n == 0) 0f else sum.toFloat() / n
            }
        }
        val prev = lastFlowGrid
        lastFlowGrid = grid
        if (prev == null || prev.size != grid.size) return 0f
        var acc = 0.0
        for (i in grid.indices) {
            acc += abs(grid[i] - prev[i])
        }
        return ((acc / grid.size) / 32.0).toFloat().coerceIn(0f, 2f)
    }

    /**
     * Lightweight pose/body motion proxy: vertical center-of-mass shift of
     * dark silhouette vs bright background (no MediaPipe Pose dependency).
     */
    private fun estimatePoseMotion(bmp: Bitmap): Float {
        val w = min(48, bmp.width)
        val h = min(64, bmp.height)
        if (w < 8 || h < 8) return 0f
        val scaled = Bitmap.createScaledBitmap(bmp, w, h, true)
        var massY = 0.0
        var mass = 0.0
        for (y in 0 until h) {
            for (x in 0 until w) {
                val l = luma(scaled.getPixel(x, y))
                val weight = (255 - l).toDouble()
                massY += y * weight
                mass += weight
            }
        }
        if (scaled !== bmp) scaled.recycle()
        if (mass < 1) return 0f
        val cy = (massY / mass) / h
        val prev = lastPoseCy
        lastPoseCy = cy
        if (prev == null) return 0f
        return (abs(cy - prev) * 6.0).toFloat().coerceIn(0f, 2f)
    }

    private var lastPoseCy: Double? = null

    fun release() {
        clearConsumers()
        workers.shutdownNow()
    }
}
