package com.oriente.oriente_native.speech

import android.content.Context
import android.content.res.AssetManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipInputStream

/**
 * Grammar-restricted continuous stop detector (one AudioRecord, 16 kHz mono).
 * Never runs alongside cloud SpeechRecognizer.
 */
class VoskStopSpotter(
    private val context: Context,
    private val onStopPhrase: (text: String, muteSpeechOnly: Boolean) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    private val running = AtomicBoolean(false)
    private var loadError: String? = null

    val isReady: Boolean get() = model != null
    val lastError: String? get() = loadError

    fun ensureModel(): Boolean {
        if (model != null) return true
        return try {
            val dir = File(context.filesDir, MODEL_DIR)
            if (!dir.exists() || !File(dir, "am").exists()) {
                unpackFromAssets(dir)
            }
            if (!dir.exists() || !File(dir, "am").exists()) {
                loadError = "Vosk model missing after unpack"
                return false
            }
            model = Model(dir.absolutePath)
            loadError = null
            true
        } catch (t: Throwable) {
            Log.e(TAG, "Vosk model load failed", t)
            loadError = t.message ?: "Vosk load failed"
            model = null
            false
        }
    }

    private fun unpackFromAssets(dest: File) {
        dest.parentFile?.mkdirs()
        val am: AssetManager = context.assets
        val names = listOf(
            "vosk/vosk-model-small-en-us-0.15.zip",
            "vosk-model-small-en-us-0.15.zip",
            "vosk/vosk-model-small-en-us.zip",
        )
        var opened = false
        for (n in names) {
            try {
                am.open(n).use { input ->
                    ZipInputStream(input).use { zis ->
                        var entry = zis.nextEntry
                        while (entry != null) {
                            val name = entry.name
                                .removePrefix("vosk-model-small-en-us-0.15/")
                                .removePrefix("vosk-model-small-en-us/")
                            if (name.isNotEmpty() && !entry.isDirectory) {
                                val out = File(dest, name)
                                out.parentFile?.mkdirs()
                                FileOutputStream(out).use { fos ->
                                    zis.copyTo(fos)
                                }
                            }
                            zis.closeEntry()
                            entry = zis.nextEntry
                        }
                    }
                }
                opened = true
                break
            } catch (_: Throwable) {
                // try next asset path
            }
        }
        if (!opened) {
            loadError = "Vosk zip not found in assets"
        }
    }

    fun start() {
        if (running.get()) return
        if (!ensureModel()) {
            Log.w(TAG, "Cannot start Vosk stop: $loadError")
            return
        }
        val m = model ?: return
        val grammar = """["stop", "stop it", "stop now", "stop looking", "you can stop",
            "cancel", "enough", "quiet", "be quiet", "go back", "stop speaking",
            "mute", "[unk]"]"""
        recognizer = Recognizer(m, 16000.0f, grammar)
        val minBuf = AudioRecord.getMinBufferSize(
            16000,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufSize = minBuf.coerceAtLeast(4096)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            16000,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufSize,
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            loadError = "AudioRecord init failed"
            rec.release()
            return
        }
        record = rec
        running.set(true)
        rec.startRecording()
        thread = Thread({
            val buf = ByteArray(bufSize)
            while (running.get()) {
                val n = rec.read(buf, 0, buf.size)
                if (n <= 0) continue
                val r = recognizer ?: break
                if (r.acceptWaveForm(buf, n)) {
                    handleJson(r.result, partial = false)
                } else {
                    handleJson(r.partialResult, partial = true)
                }
            }
        }, "vosk-stop").also { it.start() }
        Log.i(TAG, "Vosk stop spotter started")
    }

    private fun handleJson(json: String, partial: Boolean) {
        val text = extractText(json).lowercase().trim()
        if (text.isEmpty() || text == "[unk]") return
        val muteOnly = text.contains("stop speaking") ||
            text == "be quiet" ||
            text == "quiet" ||
            text == "mute"
        val hit = STOP_PHRASES.any { text == it || text.contains(it) }
        if (!hit) return
        Log.i(TAG, "Vosk stop hit partial=$partial text='$text'")
        // Act on first partial containing stop.
        running.set(false)
        main.post { onStopPhrase(text, muteOnly) }
    }

    private fun extractText(json: String): String {
        // {"text" : "..."} or {"partial" : "..."}
        val key = if (json.contains("\"partial\"")) "partial" else "text"
        val re = Regex("\"$key\"\\s*:\\s*\"([^\"]*)\"")
        return re.find(json)?.groupValues?.getOrNull(1).orEmpty()
    }

    fun stop() {
        running.set(false)
        try {
            record?.stop()
        } catch (_: Throwable) {
        }
        try {
            record?.release()
        } catch (_: Throwable) {
        }
        record = null
        thread?.join(500)
        thread = null
        try {
            recognizer?.close()
        } catch (_: Throwable) {
        }
        recognizer = null
    }

    fun release() {
        stop()
        try {
            model?.close()
        } catch (_: Throwable) {
        }
        model = null
    }

    companion object {
        private const val TAG = "VoskStop"
        private const val MODEL_DIR = "vosk-model-small-en-us"
        private val STOP_PHRASES = listOf(
            "stop speaking",
            "be quiet",
            "stop looking",
            "you can stop",
            "stop it",
            "stop now",
            "go back",
            "cancel",
            "enough",
            "quiet",
            "mute",
            "stop",
        )
    }
}
