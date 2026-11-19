package com.oriente.oriente_native.camera

import android.content.Context
import android.view.View
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CameraPreviewFactory(
    private val onCreated: (PreviewView) -> Unit,
    private val onDisposed: (PreviewView) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val preview = PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        onCreated(preview)
        return object : PlatformView {
            override fun getView(): View = preview
            override fun dispose() {
                onDisposed(preview)
            }
        }
    }
}
