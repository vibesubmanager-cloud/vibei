package com.oriente.oriente_app

import android.content.Intent
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingInject: String? = null
    private var injectChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingInject = intent?.getStringExtra(EXTRA_INJECT)
        injectChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        injectChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInjectCommand" -> {
                    val cmd = pendingInject
                    pendingInject = null
                    result.success(cmd)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val cmd = intent.getStringExtra(EXTRA_INJECT)
        pendingInject = cmd
        if (!cmd.isNullOrBlank()) {
            injectChannel?.invokeMethod("onInject", cmd)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // Hardware stop when Vosk unavailable / as backup during tasks.
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            injectChannel?.invokeMethod("volumeStop", null)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    companion object {
        const val CHANNEL = "oriente/inject"
        const val EXTRA_INJECT = "inject_command"
    }
}
