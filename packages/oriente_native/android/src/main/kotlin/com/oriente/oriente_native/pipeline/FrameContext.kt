package com.oriente.oriente_native.pipeline

import com.oriente.oriente_native.ocr.OcrBox
import com.oriente.oriente_native.vision.DetectedObject

/**
 * Shared per-frame perception cache. Built once, read by many consumers.
 */
data class FrameContext(
    val timestampMs: Long,
    val rotationDegrees: Int,
    val sharpness: Float,
    val brightness: Float,
    val motionScore: Float,
    val detections: List<DetectedObject>,
    val ocrBoxes: List<OcrBox>,
    val ocrFullText: String,
    val width: Int,
    val height: Int,
    val jpegThumb: ByteArray? = null,
    val fps: Double = 0.0,
    val detectLatencyMs: Long = 0,
    val ocrLatencyMs: Long = 0,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "timestampMs" to timestampMs,
        "rotationDegrees" to rotationDegrees,
        "sharpness" to sharpness,
        "brightness" to brightness,
        "motionScore" to motionScore,
        "width" to width,
        "height" to height,
        "fps" to fps,
        "detectLatencyMs" to detectLatencyMs,
        "ocrLatencyMs" to ocrLatencyMs,
        "detections" to detections.map { d ->
            mapOf(
                "label" to d.label,
                "score" to d.score,
                "cx" to d.cx,
                "cy" to d.cy,
                "width" to d.width,
                "height" to d.height,
            )
        },
        "ocrBoxes" to ocrBoxes.map { b ->
            mapOf(
                "text" to b.text,
                "cx" to b.cx,
                "cy" to b.cy,
                "width" to b.width,
                "height" to b.height,
                "isMatch" to b.isMatch,
                "confidence" to b.confidence,
            )
        },
        "ocrFullText" to ocrFullText,
    )
}

interface FrameConsumer {
    val id: String
    fun start()
    fun stop()
    fun onFrame(ctx: FrameContext)
}
