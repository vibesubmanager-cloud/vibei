package com.oriente.oriente_native.speech

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * HOME: one cloud recognizer session; at most one quiet soft retry; ends on silence.
 * TASK: no always-on spotter. Optional one-shot listen (no restart loop) for stop.
 */
class SpeechModule(
    private val context: Context,
    private val onAsr: (texts: List<String>, isFinal: Boolean) -> Unit,
    private val onTtsSpeakingChanged: ((Boolean) -> Unit)? = null,
    private val onErrorSpokenReady: (() -> Unit)? = null,
) {
    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var speechRate = 1.0f
    private var speechVolume = 1.0f
    /** BCP-47 tag; default English (US). Never Locale.getDefault() for ASR. */
    private var speechLanguageTag: String = "en-US"
    private var biasingStrings: ArrayList<String> = ArrayList(defaultBiasing)

    private var recognizer: SpeechRecognizer? = null
    private var listening = false
    private var wantListening = false
    private var listenWindowActive = false
    private var ttsSpeaking = false
    /** When true: one-shot listen, no soft-retry restarts. */
    private var taskMode = false
    private var minConfidence = 0.35f
    private val afterSpeak = ConcurrentHashMap<String, () -> Unit>()
    @Volatile private var speakingText: String = ""
    private var restartRunnable: Runnable? = null
    private var startAfterCancel: Runnable? = null

    /** Errors from our own cancel/stop must never restart. */
    @Volatile private var cancelledByUs = false
    private var softFailRetries = 0
    private val maxSoftRetries = 1

    val isTtsReady: Boolean get() = ttsReady
    val isVoskReady: Boolean get() = false
    val voskError: String? get() = null

    fun init() {
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                tts?.language = Locale.getDefault()
                tts?.setSpeechRate(speechRate)
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        ttsSpeaking = true
                        onTtsSpeakingChanged?.invoke(true)
                    }

                    override fun onDone(utteranceId: String?) {
                        ttsSpeaking = false
                        speakingText = ""
                        onTtsSpeakingChanged?.invoke(false)
                        val id = utteranceId ?: return
                        val cb = afterSpeak.remove(id)
                        main.post {
                            cb?.invoke()
                            maybeRestartAfterTts()
                        }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        ttsSpeaking = false
                        speakingText = ""
                        onTtsSpeakingChanged?.invoke(false)
                        val id = utteranceId ?: return
                        val cb = afterSpeak.remove(id)
                        main.post {
                            cb?.invoke()
                            maybeRestartAfterTts()
                        }
                    }
                })
            }
            onErrorSpokenReady?.invoke()
        }
    }

    private fun maybeRestartAfterTts() {
        // Never restart in task one-shot mode.
        if (!listenWindowActive || !wantListening || taskMode) return
        if (listening || cancelledByUs) return
        if (ttsSpeaking) return
        scheduleRestart(280)
    }

    fun setSpeechRate(rate: Double) {
        speechRate = rate.toFloat().coerceIn(0.5f, 2.0f)
        tts?.setSpeechRate(speechRate)
    }

    fun setSpeechVolume(volume: Double) {
        speechVolume = volume.toFloat().coerceIn(0.2f, 1.0f)
    }

    fun setTaskMode(enabled: Boolean) {
        taskMode = enabled
    }

    fun setMinConfidence(value: Double) {
        minConfidence = value.toFloat().coerceIn(0.1f, 1.0f)
    }

    fun setSpeechLanguage(tag: String) {
        speechLanguageTag = when (tag.trim()) {
            "en-GB", "en_GB" -> "en-GB"
            "en-IN", "en_IN" -> "en-IN"
            else -> "en-US"
        }
    }

    fun setBiasingStrings(phrases: List<String>) {
        if (phrases.isEmpty()) return
        biasingStrings = ArrayList(phrases)
    }

    fun stopSpeaking() {
        runCatching { tts?.stop() }
        ttsSpeaking = false
        speakingText = ""
        onTtsSpeakingChanged?.invoke(false)
        afterSpeak.clear()
    }

    fun setSpeakingText(text: String) {
        speakingText = text.lowercase(Locale.getDefault())
    }

    fun duckVolume(duck: Boolean) {
        // Ducking removed — no-op kept for channel compatibility.
    }

    fun speak(text: String, interrupt: Boolean = true) {
        val engine = tts ?: return
        if (!ttsReady) return
        speakingText = text.lowercase(Locale.getDefault())
        val mode = if (interrupt) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, speechVolume)
        }
        engine.speak(text, mode, params, UUID.randomUUID().toString())
    }

    fun speakThen(text: String, gapMs: Long = 400, after: () -> Unit) {
        val engine = tts
        if (engine == null || !ttsReady || text.isBlank()) {
            main.postDelayed(after, gapMs)
            return
        }
        val id = UUID.randomUUID().toString()
        afterSpeak[id] = {
            main.postDelayed(after, gapMs)
        }
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, speechVolume)
        }
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, id)
    }

    fun startListening() {
        main.post {
            if (taskMode) {
                startOneShotListen()
            } else {
                startHomeCloud()
            }
        }
    }

    /** One short cloud session for stop; no restart loop. */
    private fun startOneShotListen() {
        wantListening = true
        listenWindowActive = true
        softFailRetries = maxSoftRetries // block soft retries
        cancelledByUs = false
        if (ttsSpeaking) return
        if (!SpeechRecognizer.isRecognitionAvailable(context)) return
        if (listening || recognizer != null) {
            prepareRecognizerRestart(then = {
                if (wantListening && listenWindowActive && taskMode) {
                    softFailRetries = maxSoftRetries
                    beginListen()
                }
            })
            return
        }
        beginListen()
    }

    private fun startHomeCloud() {
        wantListening = true
        listenWindowActive = true
        softFailRetries = 0
        cancelledByUs = false
        if (ttsSpeaking) return
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            speak(
                "Speech recognition is not available on this phone. " +
                    "Please install or update the Google app and allow microphone.",
            )
            return
        }
        // Reuse/cancel must NOT clear wantListening — that broke 2nd home listen.
        if (listening || recognizer != null) {
            prepareRecognizerRestart(then = {
                if (wantListening && listenWindowActive && !taskMode) {
                    beginListen()
                }
            })
            return
        }
        beginListen()
    }

    private fun beginListen() {
        if (!wantListening || !listenWindowActive) return
        if (ttsSpeaking) return
        if (listening) return
        if (cancelledByUs && !wantListening) return
        cancelledByUs = false
        ensureRecognizer()
        listening = true
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, speechLanguageTag)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, speechLanguageTag)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2500)
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                1800,
            )
            if (Build.VERSION.SDK_INT >= 33 && biasingStrings.isNotEmpty()) {
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_BIASING_STRINGS,
                    ArrayList(biasingStrings),
                )
            }
        }
        try {
            Log.i(TAG, "beginListen taskMode=$taskMode softRetries=$softFailRetries")
            recognizer?.startListening(intent)
        } catch (t: Throwable) {
            Log.e(TAG, "startListening failed", t)
            listening = false
            if (!taskMode) {
                speak("Could not start speech recognition. Update the Google app and try again.")
            }
        }
    }

    private fun scheduleRestart(delayMs: Long) {
        if (!wantListening || !listenWindowActive || taskMode) return
        if (cancelledByUs) return
        restartRunnable?.let { main.removeCallbacks(it) }
        val r = Runnable {
            restartRunnable = null
            if (wantListening && listenWindowActive && !listening && !taskMode && !cancelledByUs) {
                beginListen()
            }
        }
        restartRunnable = r
        main.postDelayed(r, delayMs)
    }

    private fun ensureRecognizer() {
        if (recognizer == null) {
            recognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
                setRecognitionListener(listener)
            }
        }
    }

    private fun resetRecognizer() {
        runCatching { recognizer?.cancel() }
        runCatching { recognizer?.destroy() }
        recognizer = null
        listening = false
        ensureRecognizer()
    }

    /**
     * Cancel/destroy current recognizer, keep the new listen window flags,
     * then run [then] after a short gap (Google needs ≥~300ms after cancel).
     */
    private fun prepareRecognizerRestart(then: () -> Unit) {
        restartRunnable?.let { main.removeCallbacks(it) }
        restartRunnable = null
        startAfterCancel?.let { main.removeCallbacks(it) }
        listening = false
        cancelledByUs = true // swallow ERROR_CLIENT from this cancel
        runCatching { recognizer?.stopListening() }
        runCatching { recognizer?.cancel() }
        runCatching { recognizer?.destroy() }
        recognizer = null
        val r = Runnable {
            startAfterCancel = null
            cancelledByUs = false
            then()
        }
        startAfterCancel = r
        main.postDelayed(r, 300)
    }

    private fun stopCloudInternal(cancelled: Boolean) {
        if (cancelled) cancelledByUs = true
        wantListening = false
        listenWindowActive = false
        listening = false
        restartRunnable?.let { main.removeCallbacks(it) }
        restartRunnable = null
        startAfterCancel?.let { main.removeCallbacks(it) }
        startAfterCancel = null
        runCatching { recognizer?.stopListening() }
        runCatching { recognizer?.cancel() }
        runCatching { recognizer?.destroy() }
        recognizer = null
    }

    fun stopListening() {
        main.post {
            cancelledByUs = true
            wantListening = false
            listenWindowActive = false
            listening = false
            softFailRetries = 0
            restartRunnable?.let { main.removeCallbacks(it) }
            restartRunnable = null
            startAfterCancel?.let { main.removeCallbacks(it) }
            startAfterCancel = null
            runCatching { recognizer?.stopListening() }
            runCatching { recognizer?.cancel() }
            runCatching { recognizer?.destroy() }
            recognizer = null
        }
    }

    fun release() {
        stopListening()
        afterSpeak.clear()
        recognizer?.destroy()
        recognizer = null
        tts?.shutdown()
        tts = null
        ttsReady = false
    }

    private fun isEchoJunk(text: String): Boolean {
        val t = text.lowercase().trim()
        if (t.isEmpty()) return true
        val junk = listOf(
            "listening",
            "try again",
            "trying again",
            "cancelled",
            "vibei",
            "vivei",
            "speech recognition",
            "i'm still listening",
            "im still listening",
            "still looking",
            "lost it",
        )
        if (junk.any { t == it || t.startsWith("$it ") || (t.contains(it) && t.length < 28) }) {
            return true
        }
        if (!ttsSpeaking) return false
        val spoken = speakingText
        if (spoken.isNotEmpty() && t.length >= 3) {
            if (spoken.contains(t) || t.split(" ").all { w -> spoken.contains(w) && w.length > 2 }) {
                val isStop = t.contains("stop") || t.contains("cancel") || t.contains("quiet") ||
                    t.contains("enough") || t.contains("go back")
                if (!isStop) return true
            }
        }
        return false
    }

    /** All recognition alternatives (up to EXTRA_MAX_RESULTS), confidence-ordered when available. */
    private fun allResults(results: Bundle?): List<String> {
        val texts = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?: return emptyList()
        if (texts.isEmpty()) return emptyList()
        val scores = results.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
        val hasRealScores = scores != null &&
            scores.isNotEmpty() &&
            scores.any { it in 0.01f..1f }
        if (!hasRealScores) {
            return texts.map { it.trim() }.filter { it.isNotEmpty() }
        }
        val indexed = texts.indices.map { i ->
            val score = scores!!.getOrNull(i) ?: 0f
            Triple(i, texts[i].trim(), score)
        }.filter { it.second.isNotEmpty() }
            .sortedByDescending { it.third }
        val best = indexed.firstOrNull()?.third ?: 0f
        if (best in 0.01f..1f && best < minConfidence) {
            Log.i(TAG, "drop low_confidence best=$best")
            return emptyList()
        }
        return indexed.map { it.second }
    }

    private fun endHomeQuietly() {
        Log.i(TAG, "home listening window ended quietly")
        wantListening = false
        listenWindowActive = false
        listening = false
        softFailRetries = 0
        onAsr(emptyList(), true)
    }

    private fun endOneShotQuietly() {
        Log.i(TAG, "task one-shot listen ended")
        wantListening = false
        listenWindowActive = false
        listening = false
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            Log.i(TAG, "onReadyForSpeech")
        }

        override fun onBeginningOfSpeech() {
            Log.i(TAG, "onBeginningOfSpeech")
        }

        override fun onRmsChanged(rmsdB: Float) {}

        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
            listening = false
            Log.w(
                TAG,
                "ASR error code=$error taskMode=$taskMode want=$wantListening " +
                    "cancelledByUs=$cancelledByUs softRetries=$softFailRetries",
            )
            if (cancelledByUs || !wantListening || !listenWindowActive) {
                return
            }

            // Task one-shot: never restart.
            if (taskMode) {
                endOneShotQuietly()
                return
            }

            if (error == SpeechRecognizer.ERROR_CLIENT) {
                return
            }

            val softFail = error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT

            if (softFail) {
                if (softFailRetries < maxSoftRetries) {
                    softFailRetries++
                    scheduleRestart(1500)
                    return
                }
                endHomeQuietly()
                return
            }

            val retryable = error == SpeechRecognizer.ERROR_SERVER ||
                error == SpeechRecognizer.ERROR_NETWORK ||
                error == SpeechRecognizer.ERROR_NETWORK_TIMEOUT ||
                error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY

            if (retryable) {
                if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) {
                    resetRecognizer()
                }
                if (softFailRetries < maxSoftRetries) {
                    softFailRetries++
                    scheduleRestart(1500)
                    return
                }
                endHomeQuietly()
                return
            }

            wantListening = false
            listenWindowActive = false
            val msg = when (error) {
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    "Microphone permission is missing. Allow microphone in settings."
                SpeechRecognizer.ERROR_AUDIO ->
                    "Microphone error. Close other apps using the mic."
                else ->
                    "Speech recognition failed. Update the Google app, allow microphone, then try again."
            }
            speak(msg)
        }

        override fun onResults(results: Bundle?) {
            listening = false
            val texts = allResults(results)
            Log.i(TAG, "onResults alts=$texts")
            if (texts.isEmpty()) {
                Log.i(TAG, "drop empty final")
                if (taskMode) {
                    endOneShotQuietly()
                    return
                }
                if (wantListening && listenWindowActive && softFailRetries < maxSoftRetries) {
                    softFailRetries++
                    scheduleRestart(1500)
                } else if (wantListening && listenWindowActive) {
                    endHomeQuietly()
                }
                return
            }
            val kept = texts.filter { !isEchoJunk(it) }
            if (kept.isEmpty()) {
                Log.i(TAG, "drop echo texts=$texts")
                if (taskMode) {
                    endOneShotQuietly()
                    return
                }
                if (wantListening && listenWindowActive) scheduleRestart(400)
                return
            }
            softFailRetries = 0
            onAsr(kept, true)
            wantListening = false
            listenWindowActive = false
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val texts = allResults(partialResults).filter { !isEchoJunk(it) }
            if (texts.isEmpty()) return
            Log.i(TAG, "partial alts=$texts")
            onAsr(texts, false)
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    companion object {
        private const val TAG = "VibeiSpeech"

        private val defaultBiasing = listOf(
            "find", "look for", "search", "search for", "where is",
            "read", "describe", "stop",
            "bottle", "book", "person", "chair", "cup", "phone", "laptop",
            "cable", "battle", "award", "exhibitor", "exhibition",
        )
    }
}
