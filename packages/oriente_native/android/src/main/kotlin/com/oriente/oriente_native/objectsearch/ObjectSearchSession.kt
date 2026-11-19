package com.oriente.oriente_native.objectsearch

import android.os.Handler
import android.os.Looper
import androidx.lifecycle.LifecycleOwner
import com.oriente.oriente_native.camera.CameraModule
import com.oriente.oriente_native.guidance.GuidanceModule
import com.oriente.oriente_native.guidance.GuidanceSnapshot
import com.oriente.oriente_native.speech.SpeechModule
import com.oriente.oriente_native.vision.VisionModule

class ObjectSearchSession(
    private val camera: CameraModule,
    private val vision: VisionModule,
    private val guidance: GuidanceModule,
    private val speech: SpeechModule,
    private val onGuidance: (GuidanceSnapshot) -> Unit,
    private val onSession: (kind: String, detail: String?, error: String?) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var query: String = ""
    @Volatile private var active = false
    private var lastDirectionSpoken: String? = null

    fun start(lifecycleOwner: LifecycleOwner, query: String) {
        stop()
        this.query = query
        active = true
        guidance.reset()
        onSession("objectSearch", query, null)

        if (!vision.isReady) {
            speech.speak("Object detector is not ready.")
            onSession("idle", null, "Object detector is not ready.")
            active = false
            return
        }

        camera.start(
            lifecycleOwner = lifecycleOwner,
            onFrame = { bitmap ->
                if (!active) {
                    bitmap.recycle()
                    return@start
                }
                try {
                    val detections = vision.detect(bitmap)
                    val match = vision.bestMatch(query, detections)
                    val snap = if (match != null) {
                        guidance.update(
                            hasTarget = true,
                            label = match.label,
                            cx = match.cx,
                            cy = match.cy,
                            w = match.width,
                            h = match.height,
                        )
                    } else {
                        guidance.update(
                            hasTarget = false,
                            label = null,
                            cx = 0.5f,
                            cy = 0.5f,
                            w = 0f,
                            h = 0f,
                        )
                    }
                    main.post {
                        onGuidance(snap)
                        snap.announce?.let { speech.speak(it, interrupt = true) }
                        val dir = snap.directionSpeech
                        if (dir != null && dir != lastDirectionSpoken) {
                            lastDirectionSpoken = dir
                            speech.speak(dir, interrupt = false)
                        }
                    }
                } finally {
                    bitmap.recycle()
                }
            },
            onError = { err ->
                main.post {
                    speech.speak(err)
                    onSession("idle", null, err)
                    stop()
                }
            },
        )
    }

    fun stop() {
        active = false
        camera.stop()
        guidance.reset()
        lastDirectionSpoken = null
    }
}
