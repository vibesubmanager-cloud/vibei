package com.oriente.oriente_native.guidance

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.oriente.oriente_native.R
import kotlin.math.sqrt

data class GuidanceSnapshot(
    val phase: String,
    val proximity: Double,
    val directionSpeech: String?,
    val announce: String?,
    val label: String?,
)

/**
 * Maps detection box → proximity → beep rate, vibration, short speech.
 * See architecture §7.
 */
class GuidanceModule(private val context: Context) {
    private var soundPool: SoundPool? = null
    private var beepId = 0
    private var loaded = false

    private var lastBeepAt = 0L
    private var lastSpeechAt = 0L
    private var lastVibrateAt = 0L
    private var foundAnnounced = false
    private var returnReachedAnnounced = false

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
        vm.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    fun init() {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        soundPool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attrs).build()
        beepId = soundPool!!.load(context, R.raw.guidance_beep, 1)
        soundPool!!.setOnLoadCompleteListener { _, _, status ->
            loaded = status == 0
        }
    }

    fun reset() {
        foundAnnounced = false
        returnReachedAnnounced = false
        lastBeepAt = 0
        lastSpeechAt = 0
    }

    fun release() {
        soundPool?.release()
        soundPool = null
        loaded = false
    }

    /**
     * @param cx,cy,w,h normalized 0..1
     */
    fun update(
        hasTarget: Boolean,
        label: String?,
        cx: Float,
        cy: Float,
        w: Float,
        h: Float,
        nowMs: Long = System.currentTimeMillis(),
    ): GuidanceSnapshot {
        if (!hasTarget) {
            maybeBeep(nowMs, intervalMs = 900L, volume = 0.25f)
            return GuidanceSnapshot(
                phase = "searching",
                proximity = 0.0,
                directionSpeech = null,
                announce = null,
                label = null,
            )
        }

        val area = sqrt((w * h).toDouble()).toFloat()
        val dCenter = (sqrt(
            ((cx - 0.5f) * (cx - 0.5f) + (cy - 0.5f) * (cy - 0.5f)).toDouble(),
        ) / sqrt(0.5)).toFloat()
        val proximity = (0.55f * area + 0.45f * (1f - dCenter)).coerceIn(0f, 1f)

        val interval = when {
            proximity >= 0.85f -> 90L
            proximity >= 0.6f -> 100L + ((0.85f - proximity) * 400).toLong()
            proximity >= 0.3f -> 200L + ((0.6f - proximity) * 666).toLong()
            else -> 400L + ((0.3f - proximity) * 666).toLong()
        }
        maybeBeep(nowMs, interval, volume = 0.35f + 0.55f * proximity)
        maybeVibrate(nowMs, interval, proximity)

        var announce: String? = null
        var phase = "tracking"
        if (!foundAnnounced && proximity >= 0.55f) {
            foundAnnounced = true
            phase = "found"
            announce = "Found: ${label ?: "object"}."
            confirmHaptic()
        }

        if (area >= 0.35f && dCenter < 0.15f) {
            if (!returnReachedAnnounced) {
                returnReachedAnnounced = true
                phase = "reached"
                announce = "Reached."
                reachedHaptic()
            } else {
                phase = "reached"
            }
        }

        val direction = buildDirection(cx, cy, area)
        val speakDirection = if (
            announce == null &&
            direction != null &&
            nowMs - lastSpeechAt >= 1200L
        ) {
            lastSpeechAt = nowMs
            direction
        } else null

        return GuidanceSnapshot(
            phase = phase,
            proximity = proximity.toDouble(),
            directionSpeech = speakDirection,
            announce = announce,
            label = label,
        )
    }

    private fun buildDirection(cx: Float, cy: Float, area: Float): String? {
        val parts = mutableListOf<String>()
        when {
            cx < 0.35f -> parts += "left"
            cx > 0.65f -> parts += "right"
        }
        when {
            cy < 0.35f -> parts += "up"
            cy > 0.65f -> parts += "down"
        }
        when {
            area < 0.12f -> parts += "closer"
            area >= 0.25f && (cx < 0.4f || cx > 0.6f || cy < 0.4f || cy > 0.6f) ->
                parts += "center it"
        }
        if (parts.isEmpty()) return null
        return parts.joinToString(", ") + "."
    }

    private fun maybeBeep(nowMs: Long, intervalMs: Long, volume: Float) {
        if (!loaded) return
        if (nowMs - lastBeepAt < intervalMs) return
        lastBeepAt = nowMs
        soundPool?.play(beepId, volume, volume, 1, 0, 1f)
    }

    private fun maybeVibrate(nowMs: Long, intervalMs: Long, proximity: Float) {
        val vib = vibrator ?: return
        if (!vib.hasVibrator()) return
        if (nowMs - lastVibrateAt < intervalMs) return
        lastVibrateAt = nowMs
        val duration = (20 + 80 * proximity).toLong()
        vib.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    private fun confirmHaptic() {
        vibrator?.vibrate(
            VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE),
        )
    }

    private fun reachedHaptic() {
        vibrator?.vibrate(
            VibrationEffect.createWaveform(longArrayOf(0, 80, 40, 80, 40, 120), -1),
        )
    }
}
