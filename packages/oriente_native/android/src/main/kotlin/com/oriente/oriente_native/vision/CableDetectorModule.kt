package com.oriente.oriente_native.vision

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Optional second detector for cables. Loads
 * assets/models/cable_detector.tflite + cable_labels.txt when present.
 * Missing assets → disabled (Describe stays silent about the gap).
 */
class CableDetectorModule(private val context: Context) {
    private var detector: ObjectDetector? = null
    private val ready = AtomicBoolean(false)
    private var labels: List<String> = emptyList()
    private var scoreThreshold = 0.45f

    val isReady: Boolean get() = ready.get()
    @Volatile var lastError: String? = null
        private set

    fun init(): Boolean {
        return try {
            val am = context.assets
            try {
                am.open("models/cable_detector.tflite").close()
            } catch (_: Throwable) {
                ready.set(false)
                lastError = "cable_detector.tflite missing"
                return false
            }
            labels = loadLabels()
            val base = BaseOptions.builder()
                .setModelAssetPath("models/cable_detector.tflite")
                .build()
            val options = ObjectDetector.ObjectDetectorOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.IMAGE)
                .setScoreThreshold(scoreThreshold)
                .setMaxResults(6)
                .build()
            detector = ObjectDetector.createFromOptions(context, options)
            ready.set(true)
            lastError = null
            true
        } catch (t: Throwable) {
            ready.set(false)
            lastError = t.message
            android.util.Log.w("CableDetector", "init failed: ${t.message}")
            false
        }
    }

    fun detect(bitmap: Bitmap): List<DetectedObject> {
        val det = detector ?: return emptyList()
        if (!ready.get()) return emptyList()
        return try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            val result = det.detect(mpImage)
            val w = bitmap.width.toFloat().coerceAtLeast(1f)
            val h = bitmap.height.toFloat().coerceAtLeast(1f)
            result.detections().mapNotNull { detection ->
                val category = detection.categories().firstOrNull() ?: return@mapNotNull null
                val name = category.categoryName().ifBlank {
                    val idx = category.index()
                    if (idx in labels.indices) labels[idx] else "cable"
                }
                val thr = perClassThreshold(name)
                if (category.score() < thr) return@mapNotNull null
                val box = detection.boundingBox()
                DetectedObject(
                    label = canonicalize(name),
                    score = category.score(),
                    cx = box.centerX() / w,
                    cy = box.centerY() / h,
                    width = box.width() / w,
                    height = box.height() / h,
                )
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    fun close() {
        detector?.close()
        detector = null
        ready.set(false)
    }

    private fun loadLabels(): List<String> {
        return try {
            context.assets.open("models/cable_labels.txt").use { stream ->
                BufferedReader(InputStreamReader(stream)).readLines()
                    .map { it.trim() }
                    .filter { it.isNotEmpty() && !it.startsWith("#") }
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun perClassThreshold(name: String): Float {
        val n = name.lowercase()
        return when {
            n.contains("tangled") -> 0.55f
            n.contains("ethernet") -> 0.5f
            n.contains("hdmi") -> 0.48f
            else -> scoreThreshold
        }
    }

    private fun canonicalize(name: String): String {
        val n = name.lowercase().replace(' ', '_')
        return when {
            n.contains("usb") || n.contains("lightning") || n.contains("micro") ||
                n.contains("charging") || n.contains("hdmi") || n.contains("ethernet") ||
                n.contains("headphone") || n.contains("power") || n.contains("extension") ||
                n.contains("cable") || n.contains("cord") || n.contains("wire") ||
                n.contains("charger") || n.contains("adapter") || n.contains("strip") ->
                if (n.contains("adapter") || n.contains("charger_adapter")) {
                    "charger_adapter"
                } else if (n.contains("power_strip") || n.contains("strip")) {
                    "power_strip"
                } else {
                    "cable"
                }
            else -> name
        }
    }
}

object DetectionMerger {
    /** IoU NMS merge of primary + secondary detections. */
    fun merge(
        primary: List<DetectedObject>,
        secondary: List<DetectedObject>,
        iouThresh: Float = 0.45f,
    ): List<DetectedObject> {
        val all = (primary + secondary).sortedByDescending { it.score }
        val kept = mutableListOf<DetectedObject>()
        for (d in all) {
            var suppress = false
            for (k in kept) {
                if (iou(d, k) >= iouThresh && similarLabel(d.label, k.label)) {
                    suppress = true
                    break
                }
            }
            if (!suppress) kept.add(d)
        }
        return kept
    }

    private fun similarLabel(a: String, b: String): Boolean {
        if (a.equals(b, ignoreCase = true)) return true
        val cableish = listOf("cable", "cord", "wire", "charger", "adapter", "strip")
        val ac = cableish.any { a.contains(it, ignoreCase = true) }
        val bc = cableish.any { b.contains(it, ignoreCase = true) }
        return ac && bc
    }

    private fun iou(a: DetectedObject, b: DetectedObject): Float {
        val aL = a.cx - a.width / 2
        val aR = a.cx + a.width / 2
        val aT = a.cy - a.height / 2
        val aB = a.cy + a.height / 2
        val bL = b.cx - b.width / 2
        val bR = b.cx + b.width / 2
        val bT = b.cy - b.height / 2
        val bB = b.cy + b.height / 2
        val l = maxOf(aL, bL)
        val r = minOf(aR, bR)
        val t = maxOf(aT, bT)
        val bot = minOf(aB, bB)
        val inter = maxOf(0f, r - l) * maxOf(0f, bot - t)
        val union = a.width * a.height + b.width * b.height - inter
        return if (union <= 0f) 0f else inter / union
    }
}
