package com.oriente.oriente_native

import android.app.Activity
import android.content.SharedPreferences
import androidx.lifecycle.LifecycleOwner
import com.oriente.oriente_native.audio.AudioFeedbackModule
import com.oriente.oriente_native.camera.CameraModule
import com.oriente.oriente_native.camera.CameraPreviewFactory
import com.oriente.oriente_native.glasses.GlassesModule
import com.oriente.oriente_native.guidance.GuidanceModule
import com.oriente.oriente_native.objectsearch.ObjectSearchSession
import com.oriente.oriente_native.ocr.OcrModule
import com.oriente.oriente_native.pipeline.FrameHub
import com.oriente.oriente_native.speech.SpeechModule
import com.oriente.oriente_native.vision.CableDetectorModule
import com.oriente.oriente_native.vision.VisionModule
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import androidx.camera.view.PreviewView

/** Oriente native bridge: MethodChannel RPCs + EventChannels for streams. */
class OrienteNativePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var methods: MethodChannel
    private lateinit var asrChannel: EventChannel
    private lateinit var guidanceChannel: EventChannel
    private lateinit var sessionChannel: EventChannel
    private lateinit var glassesChannel: EventChannel
    private lateinit var framesChannel: EventChannel

    private var asrSink: EventChannel.EventSink? = null
    private var guidanceSink: EventChannel.EventSink? = null
    private var sessionSink: EventChannel.EventSink? = null
    private var glassesSink: EventChannel.EventSink? = null
    private var framesSink: EventChannel.EventSink? = null

    private var activity: Activity? = null
    private lateinit var appContext: android.content.Context
    private lateinit var prefs: SharedPreferences

    private lateinit var speech: SpeechModule
    private lateinit var vision: VisionModule
    private lateinit var cableDetector: CableDetectorModule
    private lateinit var ocr: OcrModule
    private lateinit var camera: CameraModule
    private lateinit var guidance: GuidanceModule
    private lateinit var glasses: GlassesModule
    private lateinit var audio: AudioFeedbackModule
    private lateinit var frameHub: FrameHub
    private var objectSearch: ObjectSearchSession? = null
    private var cameraSource: String = "phone"
    private var pendingPreviewView: PreviewView? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        prefs = appContext.getSharedPreferences("oriente_privacy", android.content.Context.MODE_PRIVATE)
        cameraSource = prefs.getString("cameraSource", "phone") ?: "phone"

        methods = MethodChannel(binding.binaryMessenger, "oriente/methods")
        methods.setMethodCallHandler(this)

        binding.platformViewRegistry.registerViewFactory(
            "oriente/camera_preview",
            CameraPreviewFactory(
                onCreated = { view ->
                    // camera may not be constructed yet on first attach; store then apply.
                    pendingPreviewView = view
                    if (this::camera.isInitialized) {
                        camera.setPreviewView(view)
                    }
                },
                onDisposed = { view ->
                    if (pendingPreviewView === view) pendingPreviewView = null
                    if (this::camera.isInitialized) {
                        camera.setPreviewView(null)
                    }
                },
            ),
        )

        asrChannel = EventChannel(binding.binaryMessenger, "oriente/asr")
        asrChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                asrSink = events
            }

            override fun onCancel(arguments: Any?) {
                asrSink = null
            }
        })

        guidanceChannel = EventChannel(binding.binaryMessenger, "oriente/guidance")
        guidanceChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                guidanceSink = events
            }

            override fun onCancel(arguments: Any?) {
                guidanceSink = null
            }
        })

        sessionChannel = EventChannel(binding.binaryMessenger, "oriente/session_state")
        sessionChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sessionSink = events
            }

            override fun onCancel(arguments: Any?) {
                sessionSink = null
            }
        })

        glassesChannel = EventChannel(binding.binaryMessenger, "oriente/glasses")
        glassesChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                glassesSink = events
            }

            override fun onCancel(arguments: Any?) {
                glassesSink = null
            }
        })

        framesChannel = EventChannel(binding.binaryMessenger, "oriente/frames")
        framesChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                framesSink = events
            }

            override fun onCancel(arguments: Any?) {
                framesSink = null
            }
        })

        audio = AudioFeedbackModule(appContext)
        speech = SpeechModule(
            context = appContext,
            onAsr = { texts, isFinal ->
                activity?.runOnUiThread {
                    asrSink?.success(
                        mapOf(
                            "text" to (texts.firstOrNull() ?: ""),
                            "alternatives" to texts,
                            "isFinal" to isFinal,
                        ),
                    )
                }
            },
            onTtsSpeakingChanged = { speaking ->
                // No ducking — keep tick volume steady during TTS.
                if (!speaking) audio.setDuck(1f)
            },
        )
        speech.init()

        vision = VisionModule(appContext)
        vision.init()
        cableDetector = CableDetectorModule(appContext)
        cableDetector.init() // no-op disable if assets missing
        ocr = OcrModule()

        camera = CameraModule(appContext)
        pendingPreviewView?.let { camera.setPreviewView(it) }
        frameHub = FrameHub(appContext, camera, vision, ocr, cableDetector)
        frameHub.onFrameBroadcast = { ctx ->
            framesSink?.success(ctx.toMap())
        }
        guidance = GuidanceModule(appContext)
        guidance.init()

        glasses = GlassesModule(
            context = appContext,
            onDeviceFound = { name, address, rssi ->
                glassesSink?.success(
                    mapOf(
                        "type" to "device",
                        "name" to name,
                        "address" to address,
                        "rssi" to rssi,
                    ),
                )
            },
            onConnectionChange = { state, name, address, detail ->
                glassesSink?.success(
                    mapOf(
                        "type" to "connection",
                        "state" to state,
                        "name" to name,
                        "address" to address,
                        "detail" to detail,
                    ),
                )
            },
            onLiveVideoUrl = { url ->
                glassesSink?.success(
                    mapOf(
                        "type" to "liveVideo",
                        "url" to url,
                    ),
                )
            },
        )

        objectSearch = ObjectSearchSession(
            camera = camera,
            vision = vision,
            guidance = guidance,
            speech = speech,
            onGuidance = { snap ->
                activity?.runOnUiThread {
                    guidanceSink?.success(
                        mapOf(
                            "phase" to snap.phase,
                            "proximity" to snap.proximity,
                            "directionSpeech" to snap.directionSpeech,
                            "announce" to snap.announce,
                            "label" to snap.label,
                        ),
                    )
                }
            },
            onSession = { kind, detail, error ->
                activity?.runOnUiThread {
                    sessionSink?.success(
                        mapOf(
                            "kind" to kind,
                            "detail" to detail,
                            "error" to error,
                        ),
                    )
                }
            },
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getOfflineCapabilityReport" -> {
                if (!vision.isReady) {
                    vision.init()
                }
                val vosk = speech.isVoskReady
                val detector = vision.isReady
                val summary = buildString {
                    append("VIBEI ready. ")
                    append(
                        if (detector) {
                            "Object Search works offline. "
                        } else {
                            val err = vision.lastError
                            if (err != null) {
                                append("Object detector not ready. ")
                                append(err)
                                append(' ')
                            } else {
                                append("Object detector missing. ")
                            }
                        },
                    )
                    append(
                        if (vosk) {
                            "Offline speech model installed. "
                        } else {
                            "Using system speech recognition for this build; " +
                                "Vosk offline model download is a stub. "
                        },
                    )
                    append(
                        "Say find a bottle, search text bag, nearby text, " +
                            "nearby objects, or remember this as my mug.",
                    )
                }
                result.success(
                    mapOf(
                        "cameraAvailable" to true,
                        "detectorReady" to detector,
                        "cableDetectorReady" to cableDetector.isReady,
                        "ocrReady" to ocr.isReady,
                        "voskReady" to vosk,
                        "systemAsrAvailable" to true,
                        "ttsReady" to speech.isTtsReady,
                        "onlineAvailable" to false,
                        "spokenSummary" to summary,
                        "detectorError" to vision.lastError,
                        "cableDetectorError" to cableDetector.lastError,
                    ),
                )
            }

            "speak" -> {
                val text = call.argument<String>("text") ?: ""
                val interrupt = call.argument<Boolean>("interrupt") ?: true
                speech.speak(text, interrupt)
                result.success(null)
            }

            "stopSpeaking" -> {
                speech.stopSpeaking()
                result.success(null)
            }

            "setSpeechRate" -> {
                speech.setSpeechRate(call.argument<Double>("rate") ?: 1.0)
                result.success(null)
            }

            "setSpeechVolume" -> {
                speech.setSpeechVolume(call.argument<Double>("volume") ?: 1.0)
                result.success(null)
            }

            "startListening" -> {
                speech.setTaskMode(call.argument<Boolean>("taskMode") ?: false)
                speech.startListening()
                result.success(null)
            }

            "stopListening" -> {
                speech.stopListening()
                result.success(null)
            }

            "setTaskListening" -> {
                speech.setTaskMode(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }

            "playEarcon" -> {
                when (call.argument<String>("name")) {
                    "listeningStarted" -> audio.playListeningStarted()
                    "listeningEnded" -> audio.playListeningEnded()
                    "error" -> audio.playError()
                    "found" -> audio.playFoundChirp()
                    "reached" -> audio.playReached()
                    "thinkingStart" -> audio.playThinkingLoopStart()
                    "thinkingStop" -> audio.stopThinkingLoop()
                    else -> {}
                }
                result.success(null)
            }

            "setSearchTicks" -> {
                val rate = call.argument<Double>("rateHz") ?: 0.0
                val pan = call.argument<Double>("pan") ?: 0.0
                if (rate <= 0) audio.stopTicks() else audio.setTickPattern(rate, pan)
                result.success(null)
            }

            "setAudioFeedbackPrefs" -> {
                audio.setTickSoundEnabled(call.argument<Boolean>("tickSound") ?: true)
                audio.setVibrationEnabled(call.argument<Boolean>("vibration") ?: true)
                result.success(null)
            }

            "vibrate" -> {
                audio.vibrate((call.argument<Int>("ms") ?: 20))
                result.success(null)
            }

            "setKeepScreenOn" -> {
                val on = call.argument<Boolean>("enabled") ?: false
                activity?.runOnUiThread {
                    if (on) {
                        activity?.window?.addFlags(
                            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                        )
                    } else {
                        activity?.window?.clearFlags(
                            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                        )
                    }
                }
                result.success(null)
            }

            "startFramePipeline" -> {
                val act = activity
                if (act is LifecycleOwner) {
                    frameHub.bindLifecycle(act)
                    frameHub.perfOverlay = call.argument<Boolean>("perfOverlay") ?: false
                    // Keep pipeline warm with a no-op consumer so CameraX runs.
                    frameHub.addConsumer(
                        object : com.oriente.oriente_native.pipeline.FrameConsumer {
                            override val id: String = "flutter_broadcast"
                            override fun start() {}
                            override fun stop() {}
                            override fun onFrame(
                                ctx: com.oriente.oriente_native.pipeline.FrameContext,
                            ) {
                            }
                        },
                    )
                    result.success(true)
                } else {
                    result.error("no_lifecycle", "Activity missing", null)
                }
            }

            "stopFramePipeline" -> {
                frameHub.clearConsumers()
                result.success(null)
            }

            "getPipelinePerf" -> {
                val ctx = frameHub.lastContext
                val rt = Runtime.getRuntime()
                val memMb =
                    (rt.totalMemory() - rt.freeMemory()).toDouble() / (1024.0 * 1024.0)
                result.success(
                    mapOf(
                        "fps" to (ctx?.fps ?: 0.0),
                        "detectLatencyMs" to (ctx?.detectLatencyMs ?: 0L),
                        "ocrLatencyMs" to (ctx?.ocrLatencyMs ?: 0L),
                        "memoryMb" to (frameHub.lastMemoryMb.takeIf { it > 0 } ?: memMb),
                        "motionScore" to (ctx?.motionScore ?: 0f),
                        "width" to (ctx?.width ?: 0),
                        "height" to (ctx?.height ?: 0),
                    ),
                )
            }

            "grabLatestJpeg" -> {
                val maxEdge = call.argument<Int>("maxEdge") ?: 1024
                val quality = call.argument<Int>("quality") ?: 75
                frameHub.setJpegCapture(true, maxEdge, quality)
                val bytes = frameHub.grabJpeg(maxEdge, quality)
                if (bytes == null) {
                    result.success(null)
                } else {
                    result.success(bytes)
                }
            }

            "grabLatestFrame" -> {
                val ctx = frameHub.lastContext
                if (ctx == null) {
                    result.success(null)
                } else {
                    result.success(ctx.toMap())
                }
            }

            "pingBackend" -> {
                // Lightweight reachability for ConnectivityService (no spoken result).
                val url = call.argument<String>("url") ?: ""
                if (url.isBlank()) {
                    result.success(mapOf("ok" to false))
                    return
                }
                Thread {
                    try {
                        val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                        conn.connectTimeout = 2500
                        conn.readTimeout = 2500
                        conn.requestMethod = "GET"
                        val code = conn.responseCode
                        conn.disconnect()
                        activity?.runOnUiThread {
                            result.success(mapOf("ok" to (code in 200..499)))
                        }
                    } catch (_: Throwable) {
                        activity?.runOnUiThread {
                            result.success(mapOf("ok" to false))
                        }
                    }
                }.start()
            }

            "detectObjects" -> {
                // Flutter camera page sends a JPEG; return boxes for overlay.
                if (!vision.isReady) {
                    vision.init()
                }
                if (!vision.isReady) {
                    result.error(
                        "detector",
                        vision.lastError ?: "Object detector not ready",
                        null,
                    )
                    return
                }
                val bytes = call.argument<ByteArray>("jpeg")
                if (bytes == null || bytes.isEmpty()) {
                    result.error("bad_image", "Empty image", null)
                    return
                }
                val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("bad_image", "Could not decode image", null)
                    return
                }
                try {
                    val detections = vision.detect(bitmap)
                    val query = call.argument<String>("query") ?: ""
                    val match = if (query.isNotBlank()) {
                        vision.bestMatch(query, detections)
        } else {
                        null
                    }
                    result.success(
                        mapOf(
                            "detections" to detections.map { d ->
                                mapOf(
                                    "label" to d.label,
                                    "score" to d.score,
                                    "cx" to d.cx,
                                    "cy" to d.cy,
                                    "width" to d.width,
                                    "height" to d.height,
                                    "isTarget" to (
                                        match != null &&
                                            d.label == match.label &&
                                            kotlin.math.abs(d.cx - match.cx) < 0.02f &&
                                            kotlin.math.abs(d.cy - match.cy) < 0.02f
                                        ),
                                )
                            },
                            "hasTarget" to (match != null),
                            "targetLabel" to match?.label,
                        ),
                    )
                } finally {
                    bitmap.recycle()
                }
            }

            "recognizeText" -> {
                val bytes = call.argument<ByteArray>("jpeg")
                if (bytes == null || bytes.isEmpty()) {
                    result.error("bad_image", "Empty image", null)
                    return
                }
                val query = call.argument<String>("query") ?: ""
                val rotation = call.argument<Int>("rotationDegrees") ?: -1
                // Decode+EXIF rotate inside OcrModule (BitmapFactory alone ignored orientation).
                Thread {
                    try {
                        val frame = ocr.recognize(bytes, query, rotation)
                        activity?.runOnUiThread {
                            result.success(
                                mapOf(
                                    "boxes" to frame.boxes.map { b ->
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
                                    "fullText" to frame.fullText,
                                    "hasMatch" to frame.hasMatch,
                                    "rotationApplied" to frame.rotationApplied,
                                ),
                            )
                        }
                    } catch (t: Throwable) {
                        activity?.runOnUiThread {
                            result.error("ocr", t.message, null)
                        }
                    }
                }.start()
            }

            "setTorch" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val ok = if (this::camera.isInitialized) camera.setTorch(enabled) else false
                result.success(ok)
            }

            "duckSpeech" -> {
                val duck = call.argument<Boolean>("duck") ?: false
                speech.duckVolume(duck)
                result.success(null)
            }

            "setSpeakingText" -> {
                speech.setSpeakingText(call.argument<String>("text") ?: "")
                result.success(null)
            }

            "startObjectSearch" -> {
                val query = call.argument<String>("query") ?: ""
                val act = activity
                if (act == null) {
                    result.error("no_activity", "Activity not attached", null)
                    return
                }
                if (act !is LifecycleOwner) {
                    result.error("no_lifecycle", "Activity is not a LifecycleOwner", null)
                    return
                }
                if (cameraSource == "glasses") {
                    if (!glasses.isBound()) {
                        speech.speak(
                            "Smart glasses are not connected. Pair glasses first, or switch to phone camera.",
                            interrupt = true,
                        )
                        result.error("glasses_unbound", "Glasses not connected", null)
                        return
                    }
                    glasses.startLiveVideo()
                    speech.speak(
                        "Using smart glasses. Connecting glass camera over Wi-Fi.",
                        interrupt = true,
                    )
                    // Glass live frames → MediaPipe lands next; phone camera continues detection now.
                }
                objectSearch?.start(act, query)
                result.success(null)
            }

            "cancel" -> {
                objectSearch?.stop()
                speech.stopSpeaking()
                speech.stopListening()
                speech.setTaskMode(false)
                audio.stopTicks()
                audio.stopThinkingLoop()
                runCatching { camera.setTorch(false) }
                if (cameraSource == "glasses") {
                    glasses.stopLiveVideo()
                }
                activity?.runOnUiThread {
                    sessionSink?.success(
                        mapOf("kind" to "idle", "detail" to null, "error" to null),
                    )
                }
                result.success(null)
            }

            "setCameraSource" -> {
                val source = call.argument<String>("source") ?: "phone"
                cameraSource = if (source == "glasses") "glasses" else "phone"
                prefs.edit().putString("cameraSource", cameraSource).apply()
                result.success(mapOf("source" to cameraSource))
            }

            "getCameraSource" -> {
                result.success(mapOf("source" to cameraSource))
            }

            "initGlassesSdk" -> {
                val app = appContext.applicationContext as? android.app.Application
                if (app == null) {
                    result.error("no_app", "Application context missing", null)
                    return
                }
                val actName = activity?.javaClass?.name
                    ?: "com.oriente.oriente_app.MainActivity"
                val ok = glasses.init(
                    application = app,
                    notificationActivityClass = actName,
                    appName = "VIBEI",
                    appIcon = android.R.drawable.ic_menu_camera,
                )
                result.success(
                    buildMap {
                        put("ok", ok)
                        putAll(glasses.statusMap())
                    },
                )
            }

            "glassesStartScan" -> {
                result.success(glasses.startScan())
            }

            "glassesStopScan" -> {
                glasses.stopScan()
                result.success(null)
            }

            "glassesBind" -> {
                val name = call.argument<String>("name") ?: ""
                val address = call.argument<String>("address") ?: ""
                result.success(glasses.bind(name, address))
            }

            "glassesDisconnect" -> {
                glasses.disconnect()
                result.success(null)
            }

            "glassesUnbind" -> {
                glasses.unbind()
                result.success(null)
            }

            "glassesAutoConnect" -> {
                glasses.autoConnect()
                result.success(null)
            }

            "glassesStatus" -> {
                result.success(glasses.statusMap())
            }

            "glassesPullConfig" -> {
                result.success(glasses.pullDeviceParams())
            }

            "glassesStartLiveVideo" -> {
                result.success(glasses.startLiveVideo())
            }

            "glassesStopLiveVideo" -> {
                glasses.stopLiveVideo()
                result.success(null)
            }

            "glassesApplyButtons" -> {
                val ok = glasses.applyButtonMapping(
                    leftSingle = call.argument<String>("leftSingle") ?: "listen",
                    leftDouble = call.argument<String>("leftDouble") ?: "find",
                    leftLong = call.argument<String>("leftLong") ?: "cancel",
                    rightSingle = call.argument<String>("rightSingle") ?: "photo",
                    rightDouble = call.argument<String>("rightDouble") ?: "video",
                    rightLong = call.argument<String>("rightLong") ?: "audio",
                )
                result.success(ok)
            }

            "getPrivacySettings" -> {
                result.success(
                    mapOf(
                        "onlineVisionConsent" to prefs.getBoolean("onlineVisionConsent", false),
                        "onlineChatConsent" to prefs.getBoolean("onlineChatConsent", false),
                        "speechRate" to prefs.getFloat("speechRate", 1f).toDouble(),
                        "speechVolume" to prefs.getFloat("speechVolume", 1f).toDouble(),
                        "speechLanguage" to prefs.getString("speechLanguage", "en-US"),
                    ),
                )
            }

            "setPrivacySettings" -> {
                val lang = call.argument<String>("speechLanguage") ?: "en-US"
                prefs.edit()
                    .putBoolean(
                        "onlineVisionConsent",
                        call.argument<Boolean>("onlineVisionConsent") ?: false,
                    )
                    .putBoolean(
                        "onlineChatConsent",
                        call.argument<Boolean>("onlineChatConsent") ?: false,
                    )
                    .putFloat(
                        "speechRate",
                        (call.argument<Double>("speechRate") ?: 1.0).toFloat(),
                    )
                    .putFloat(
                        "speechVolume",
                        (call.argument<Double>("speechVolume") ?: 1.0).toFloat(),
                    )
                    .putString("speechLanguage", lang)
                    .apply()
                speech.setSpeechLanguage(lang)
                result.success(null)
            }

            "setSpeechBiasing" -> {
                val phrases = call.argument<List<String>>("phrases") ?: emptyList()
                speech.setBiasingStrings(phrases)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        objectSearch?.stop()
        glasses.release()
        camera.stop()
        frameHub.release()
        vision.close()
        ocr.close()
        guidance.release()
        audio.release()
        speech.release()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val act = binding.activity
        if (act is LifecycleOwner) {
            frameHub.bindLifecycle(act)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        val act = binding.activity
        if (act is LifecycleOwner) {
            frameHub.bindLifecycle(act)
        }
    }

    override fun onDetachedFromActivity() {
        objectSearch?.stop()
        frameHub.stop()
        activity = null
    }
}
