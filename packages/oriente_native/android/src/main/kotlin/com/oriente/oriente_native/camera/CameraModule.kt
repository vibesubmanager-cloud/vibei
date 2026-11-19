package com.oriente.oriente_native.camera

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.Looper
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/**
 * CameraX preview + analysis on one session (no second camera open).
 * Analysis capped ~8 FPS for thermal/battery.
 */
class CameraModule(private val context: Context) {
    private var cameraProvider: ProcessCameraProvider? = null
    private var analysis: ImageAnalysis? = null
    private var preview: Preview? = null
    private var camera: Camera? = null
    private var analyzerExecutor: ExecutorService? = null
    private val running = AtomicBoolean(false)
    private var lastFrameAt = 0L
    private var minFrameIntervalMs = 125L // ~8 FPS
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var torchOn = false

    @Volatile private var previewView: PreviewView? = null
    private var lifecycleOwner: LifecycleOwner? = null
    private var onFrameCb: ((Bitmap) -> Unit)? = null
    private var onErrorCb: ((String) -> Unit)? = null

    fun setPreviewView(view: PreviewView?) {
        previewView = view
        if (running.get()) {
            main.post { bindUseCases() }
        }
    }

    fun start(
        lifecycleOwner: LifecycleOwner,
        onFrame: (Bitmap) -> Unit,
        onError: (String) -> Unit,
    ) {
        this.lifecycleOwner = lifecycleOwner
        this.onFrameCb = onFrame
        this.onErrorCb = onError
        if (running.getAndSet(true)) {
            main.post { bindUseCases() }
            return
        }
        analyzerExecutor = Executors.newSingleThreadExecutor()

        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                cameraProvider = future.get()
                bindUseCases()
            } catch (t: Throwable) {
                running.set(false)
                onError("Could not start camera: ${t.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindUseCases() {
        val owner = lifecycleOwner ?: return
        val provider = cameraProvider ?: return
        if (!running.get()) return

        try {
            provider.unbindAll()

            analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()
                .also { ia ->
                    val exec = analyzerExecutor ?: return
                    ia.setAnalyzer(exec) { proxy ->
                        try {
                            val now = System.currentTimeMillis()
                            if (now - lastFrameAt < minFrameIntervalMs) {
                                proxy.close()
                                return@setAnalyzer
                            }
                            lastFrameAt = now
                            val bmp = imageProxyToBitmap(proxy)
                            proxy.close()
                            if (bmp != null) onFrameCb?.invoke(bmp)
                        } catch (t: Throwable) {
                            runCatching { proxy.close() }
                            onErrorCb?.invoke("Camera frame error: ${t.message}")
                        }
                    }
                }

            val view = previewView
            camera = if (view != null) {
                preview = Preview.Builder().build().also { p ->
                    p.surfaceProvider = view.surfaceProvider
                }
                provider.bindToLifecycle(
                    owner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis,
                )
            } else {
                preview = null
                provider.bindToLifecycle(
                    owner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    analysis,
                )
            }
            if (torchOn) {
                runCatching { camera?.cameraControl?.enableTorch(true) }
            }
        } catch (t: Throwable) {
            onErrorCb?.invoke("Could not start camera: ${t.message}")
        }
    }

    fun setTorch(enabled: Boolean): Boolean {
        torchOn = enabled
        val cam = camera ?: return false
        val hasFlash = cam.cameraInfo.hasFlashUnit()
        if (!hasFlash) return false
        return try {
            cam.cameraControl.enableTorch(enabled)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun stop() {
        running.set(false)
        runCatching { camera?.cameraControl?.enableTorch(false) }
        torchOn = false
        try {
            analysis?.clearAnalyzer()
            cameraProvider?.unbindAll()
        } catch (_: Throwable) {
        }
        analysis = null
        preview = null
        camera = null
        analyzerExecutor?.shutdownNow()
        analyzerExecutor = null
        lifecycleOwner = null
        onFrameCb = null
        onErrorCb = null
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun imageProxyToBitmap(image: ImageProxy): Bitmap? {
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer
        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()
        val nv21 = ByteArray(ySize + uSize + vSize)
        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        val yuv = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        val out = ByteArrayOutputStream()
        yuv.compressToJpeg(Rect(0, 0, image.width, image.height), 60, out)
        val bytes = out.toByteArray()
        var bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: return null

        val rotation = image.imageInfo.rotationDegrees
        if (rotation != 0) {
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (rotated != bitmap) bitmap.recycle()
            bitmap = rotated
        }

        val longEdge = max(bitmap.width, bitmap.height)
        if (longEdge > 640) {
            val scale = 640f / longEdge
            val w = (bitmap.width * scale).toInt().coerceAtLeast(1)
            val h = (bitmap.height * scale).toInt().coerceAtLeast(1)
            val scaled = Bitmap.createScaledBitmap(bitmap, w, h, true)
            if (scaled != bitmap) bitmap.recycle()
            bitmap = scaled
        }
        return bitmap
    }
}
