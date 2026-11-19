package com.oriente.oriente_native.vision

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetectorResult
import java.util.concurrent.atomic.AtomicBoolean

data class DetectedObject(
    val label: String,
    val score: Float,
    val cx: Float,
    val cy: Float,
    val width: Float,
    val height: Float,
)

/**
 * On-device object detection via MediaPipe EfficientDet-Lite0 (Apache-2.0).
 * Bundled asset: assets/models/efficientdet_lite0.tflite
 */
class VisionModule(private val context: Context) {
    private var detector: ObjectDetector? = null
    private val ready = AtomicBoolean(false)

    val isReady: Boolean get() = ready.get()
    @Volatile
    var lastError: String? = null
        private set

    fun init(): Boolean {
        return try {
            val base = BaseOptions.builder()
                .setModelAssetPath("models/efficientdet_lite0.tflite")
                .build()
            val options = ObjectDetector.ObjectDetectorOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.IMAGE)
                .setScoreThreshold(0.35f)
                .setMaxResults(8)
                .build()
            detector = ObjectDetector.createFromOptions(context, options)
            ready.set(true)
            lastError = null
            true
        } catch (t: Throwable) {
            ready.set(false)
            val abi = android.os.Build.SUPPORTED_ABIS.joinToString()
            lastError = buildString {
                append(t.message ?: t.javaClass.simpleName)
                append(" (device ABI: ")
                append(abi)
                append(')')
                if (abi.contains("x86") &&
                    (t.message?.contains("mediapipe", ignoreCase = true) == true ||
                        t.message?.contains("dlopen", ignoreCase = true) == true ||
                        t.message?.contains("not found", ignoreCase = true) == true)
                ) {
                    append(
                        ". Object detection needs a real phone or ARM emulator; " +
                            "this x86 simulator cannot load MediaPipe.",
                    )
                }
            }
            android.util.Log.e("VisionModule", "init failed: $lastError", t)
            false
        }
    }

    fun detect(bitmap: Bitmap): List<DetectedObject> {
        val det = detector ?: return emptyList()
        if (!ready.get()) return emptyList()
        val mpImage = BitmapImageBuilder(bitmap).build()
        val result: ObjectDetectorResult = det.detect(mpImage)
        val w = bitmap.width.toFloat().coerceAtLeast(1f)
        val h = bitmap.height.toFloat().coerceAtLeast(1f)
        return result.detections().mapNotNull { detection ->
            val category = detection.categories().firstOrNull() ?: return@mapNotNull null
            val box = detection.boundingBox()
            val bw = box.width() / w
            val bh = box.height() / h
            DetectedObject(
                label = category.categoryName(),
                score = category.score(),
                cx = (box.centerX()) / w,
                cy = (box.centerY()) / h,
                width = bw,
                height = bh,
            )
        }
    }

    /** Fuzzy / synonym-aware match against COCO labels. */
    fun bestMatch(query: String, detections: List<DetectedObject>): DetectedObject? {
        val q = normalize(query)
        if (q.isEmpty() || detections.isEmpty()) return null

        var best: DetectedObject? = null
        var bestScore = 0.0

        for (d in detections) {
            val label = normalize(d.label)
            val sim = similarity(q, label)
            val synonymBonus = if (synonymHit(q, label)) 0.25 else 0.0
            val score = sim + synonymBonus + d.score * 0.1
            if (score > bestScore) {
                bestScore = score
                best = d
            }
        }
        return if (bestScore >= 0.55) best else null
    }

    fun close() {
        detector?.close()
        detector = null
        ready.set(false)
    }

    private fun normalize(s: String): String =
        s.lowercase().replace(Regex("[^a-z0-9\\s]"), " ").replace(Regex("\\s+"), " ").trim()

    private fun synonymHit(query: String, label: String): Boolean {
        val map = mapOf(
            "keys" to listOf("key"),
            "key" to listOf("keys"),
            "bottle" to listOf("bottle", "wine glass"),
            "phone" to listOf("cell phone"),
            "cell phone" to listOf("phone"),
            "tv" to listOf("tv", "television"),
            "remote" to listOf("remote"),
            "cup" to listOf("cup", "mug"),
            "glasses" to listOf("eyeglasses"), // may not be in COCO — personal objects later
            "person" to listOf("person"),
            "chair" to listOf("chair"),
            "book" to listOf("book"),
            "laptop" to listOf("laptop"),
            "mouse" to listOf("mouse"),
            "keyboard" to listOf("keyboard"),
            "backpack" to listOf("backpack"),
            "handbag" to listOf("handbag", "bag"),
            "bag" to listOf("handbag", "backpack", "suitcase"),
        )
        val candidates = map[query] ?: emptyList()
        if (candidates.any { label.contains(it) || it.contains(label) }) return true
        if (label.contains(query) || query.contains(label)) return true
        return false
    }

    private fun similarity(a: String, b: String): Double {
        if (a == b) return 1.0
        if (a.isEmpty() || b.isEmpty()) return 0.0
        val dist = levenshtein(a, b)
        val maxLen = maxOf(a.length, b.length)
        return 1.0 - dist.toDouble() / maxLen
    }

    private fun levenshtein(a: String, b: String): Int {
        val prev = IntArray(b.length + 1) { it }
        val curr = IntArray(b.length + 1)
        for (i in a.indices) {
            curr[0] = i + 1
            for (j in b.indices) {
                val cost = if (a[i] == b[j]) 0 else 1
                curr[j + 1] = minOf(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost)
            }
            for (j in prev.indices) prev[j] = curr[j]
        }
        return prev[b.length]
    }
}
