package com.oriente.oriente_native.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlin.math.PI
import kotlin.math.sin

/**
 * Soft earcons, stereo search ticks, and haptics.
 * Vibration ONLY while search ticks are running (never on HOME).
 */
class AudioFeedbackModule(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var duck = 1f
    @Volatile private var tickEnabled = true
    @Volatile private var vibEnabled = true
    @Volatile private var tickRateHz = 0.0
    @Volatile private var tickPan = 0.0
    @Volatile private var tickVibrate = false
    private var tickRunnable: Runnable? = null
    private var reachedToneTrack: AudioTrack? = null

    fun setTickSoundEnabled(enabled: Boolean) {
        tickEnabled = enabled
    }

    fun setVibrationEnabled(enabled: Boolean) {
        vibEnabled = enabled
    }

    fun setDuck(factor: Float) {
        duck = factor.coerceIn(0.05f, 1f)
    }

    fun playListeningStarted() {
        playTone(880.0, 70, 0.22, pan = 0.0)
        main.postDelayed({ playTone(1175.0, 90, 0.2, pan = 0.0) }, 80)
    }

    fun playListeningEnded() {
        playTone(660.0, 80, 0.18, pan = 0.0)
        main.postDelayed({ playTone(440.0, 110, 0.16, pan = 0.0) }, 90)
    }

    fun playError() {
        playTone(300.0, 140, 0.2, pan = 0.0)
    }

    fun playFoundChirp() {
        playTone(990.0, 50, 0.25, pan = 0.0)
        main.postDelayed({ playTone(1320.0, 60, 0.22, pan = 0.0) }, 70)
    }

    fun playReached() {
        playTone(1200.0, 45, 0.28, pan = -0.2)
        main.postDelayed({ playTone(1200.0, 45, 0.28, pan = 0.2) }, 90)
        startSoftTone()
    }

    fun playThinkingLoopStart() {
        // Soft audio only — never vibrate outside Search.
        setTickPattern(1.4, 0.0, withVibration = false)
    }

    fun stopThinkingLoop() {
        stopTicks()
        stopSoftTone()
    }

    fun setTickPattern(rateHz: Double, pan: Double, withVibration: Boolean = true) {
        tickRateHz = rateHz.coerceIn(0.0, 12.0)
        tickPan = pan.coerceIn(-1.0, 1.0)
        tickVibrate = withVibration
        if (tickRateHz <= 0) {
            stopTicks()
            return
        }
        if (tickRunnable != null) return
        val r = object : Runnable {
            override fun run() {
                val hz = tickRateHz
                if (hz <= 0) {
                    tickRunnable = null
                    return
                }
                if (tickEnabled) {
                    playTone(720.0, 28, 0.12 * duck, pan = tickPan)
                }
                // Vibration only for Search ticks (withVibration=true).
                if (tickVibrate && vibEnabled && hz >= 0.5) {
                    vibrate(14)
                }
                val delay = (1000.0 / hz).toLong().coerceIn(80, 2000)
                main.postDelayed(this, delay)
            }
        }
        tickRunnable = r
        main.post(r)
    }

    fun stopTicks() {
        tickRateHz = 0.0
        tickVibrate = false
        tickRunnable?.let { main.removeCallbacks(it) }
        tickRunnable = null
        stopSoftTone()
    }

    fun vibrate(ms: Int) {
        if (!vibEnabled || ms <= 0) return
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= 31) {
                val vm = context.getSystemService(VibratorManager::class.java)
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            } ?: return
            if (Build.VERSION.SDK_INT >= 26) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(
                        ms.toLong(),
                        VibrationEffect.DEFAULT_AMPLITUDE,
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(ms.toLong())
            }
        } catch (_: Throwable) {
        }
    }

    private fun startSoftTone() {
        stopSoftTone()
        Thread {
            try {
                val sampleRate = 22050
                val freq = 520.0
                val bufFrames = sampleRate / 10
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                            .build(),
                    )
                    .setBufferSizeInBytes(bufFrames * 4)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
                reachedToneTrack = track
                track.play()
                var phase = 0.0
                val step = 2 * PI * freq / sampleRate
                val shortBuf = ShortArray(bufFrames * 2)
                while (reachedToneTrack === track) {
                    val amp = (1800 * duck).toInt().coerceIn(200, 4000)
                    for (i in 0 until bufFrames) {
                        val s = (sin(phase) * amp).toInt().toShort()
                        phase += step
                        shortBuf[i * 2] = s
                        shortBuf[i * 2 + 1] = s
                    }
                    track.write(shortBuf, 0, shortBuf.size)
                }
            } catch (_: Throwable) {
            }
        }.start()
    }

    private fun stopSoftTone() {
        val t = reachedToneTrack
        reachedToneTrack = null
        try {
            t?.stop()
            t?.release()
        } catch (_: Throwable) {
        }
    }

    private fun playTone(freq: Double, durationMs: Int, volume: Double, pan: Double) {
        Thread {
            try {
                val sampleRate = 22050
                val n = (sampleRate * durationMs / 1000.0).toInt().coerceAtLeast(1)
                val leftGain = ((1.0 - pan) / 2.0).coerceIn(0.0, 1.0)
                val rightGain = ((1.0 + pan) / 2.0).coerceIn(0.0, 1.0)
                val buf = ShortArray(n * 2)
                val amp = (Short.MAX_VALUE * volume * duck).toInt().coerceIn(0, 12000)
                for (i in 0 until n) {
                    val env = when {
                        i < n / 10 -> i.toDouble() / (n / 10.0)
                        i > n * 8 / 10 -> (n - i).toDouble() / (n / 10.0)
                        else -> 1.0
                    }
                    val s = (sin(2 * PI * freq * i / sampleRate) * amp * env).toInt().toShort()
                    buf[i * 2] = (s * leftGain).toInt().toShort()
                    buf[i * 2 + 1] = (s * rightGain).toInt().toShort()
                }
                val track = AudioTrack(
                    AudioManager.STREAM_MUSIC,
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_STEREO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    buf.size * 2,
                    AudioTrack.MODE_STATIC,
                )
                track.write(buf, 0, buf.size)
                track.play()
                Thread.sleep(durationMs.toLong() + 20)
                track.stop()
                track.release()
            } catch (_: Throwable) {
            }
        }.start()
    }

    fun release() {
        stopTicks()
        stopSoftTone()
    }
}
