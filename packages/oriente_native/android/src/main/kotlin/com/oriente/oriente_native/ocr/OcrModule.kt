package com.oriente.oriente_native.ocr

import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.ByteArrayInputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

data class OcrBox(
    val text: String,
    val cx: Float,
    val cy: Float,
    val width: Float,
    val height: Float,
    val isMatch: Boolean,
    val confidence: Float,
)

data class OcrFrame(
    val boxes: List<OcrBox>,
    val fullText: String,
    val hasMatch: Boolean,
    val rotationApplied: Int,
)

/**
 * Offline OCR via ML Kit. Applies EXIF / caller rotation so text is upright.
 */
class OcrModule {
    private val recognizer =
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    @Volatile
    var lastError: String? = null
        private set

    val isReady: Boolean get() = true

    fun recognize(
        jpeg: ByteArray,
        query: String = "",
        rotationDegrees: Int = -1,
    ): OcrFrame {
        val decoded = android.graphics.BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
            ?: return OcrFrame(emptyList(), "", false, 0).also {
                lastError = "decode failed"
            }
        val rot = if (rotationDegrees >= 0) {
            rotationDegrees
        } else {
            readExifRotation(jpeg)
        }
        val bitmap = if (rot == 0) decoded else rotateBitmap(decoded, rot).also {
            if (it !== decoded) decoded.recycle()
        }
        return try {
            recognizeBitmap(bitmap, query, rot)
        } finally {
            bitmap.recycle()
        }
    }

    fun recognizeBitmap(bitmap: Bitmap, query: String = "", rotationApplied: Int = 0): OcrFrame {
        val latch = CountDownLatch(1)
        val out = AtomicReference(OcrFrame(emptyList(), "", false, rotationApplied))
        try {
            // Bitmap already oriented; pass 0 to ML Kit.
            val image = InputImage.fromBitmap(bitmap, 0)
            val w = bitmap.width.toFloat().coerceAtLeast(1f)
            val h = bitmap.height.toFloat().coerceAtLeast(1f)
            val q = query.trim().lowercase()

            recognizer.process(image)
                .addOnSuccessListener { result ->
                    val boxes = mutableListOf<OcrBox>()
                    val full = StringBuilder()
                    for (block in result.textBlocks) {
                        for (line in block.lines) {
                            val box = line.boundingBox ?: continue
                            val text = line.text.trim()
                            if (text.isEmpty()) continue
                            if (full.isNotEmpty()) full.append(' ')
                            full.append(text)
                            // ML Kit Latin lines may not expose confidence on all versions.
                            boxes.add(
                                OcrBox(
                                    text = text,
                                    cx = box.centerX() / w,
                                    cy = box.centerY() / h,
                                    width = box.width() / w,
                                    height = box.height() / h,
                                    isMatch = false,
                                    confidence = 0.5f,
                                ),
                            )
                        }
                    }
                    // Matching is refined in Dart; mark naive contains here too.
                    var any = false
                    if (q.isNotEmpty()) {
                        for (i in boxes.indices) {
                            val t = boxes[i].text.lowercase()
                            val hit = t.contains(q) || q.split(' ').any { it.length >= 3 && t.contains(it) }
                            if (hit) {
                                boxes[i] = boxes[i].copy(isMatch = true)
                                any = true
                            }
                        }
                    }
                    out.set(
                        OcrFrame(
                            boxes,
                            full.toString(),
                            any || (q.isEmpty() && boxes.isNotEmpty()),
                            rotationApplied,
                        ),
                    )
                    lastError = null
                    latch.countDown()
                }
                .addOnFailureListener { e ->
                    lastError = e.message
                    out.set(OcrFrame(emptyList(), "", false, rotationApplied))
                    latch.countDown()
                }
            latch.await(6, TimeUnit.SECONDS)
        } catch (t: Throwable) {
            lastError = t.message
            out.set(OcrFrame(emptyList(), "", false, rotationApplied))
        }
        return out.get()
    }

    private fun readExifRotation(jpeg: ByteArray): Int {
        return try {
            val exif = ExifInterface(ByteArrayInputStream(jpeg))
            when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (_: Throwable) {
            0
        }
    }

    private fun rotateBitmap(src: Bitmap, degrees: Int): Bitmap {
        if (degrees % 360 == 0) return src
        val m = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
    }

    fun close() {
        runCatching { recognizer.close() }
    }
}
