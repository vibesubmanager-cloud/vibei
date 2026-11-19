package com.oriente.oriente_native.glasses

import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.xsx.rdbluetooth.bean.ButtonFunctionBean
import com.xsx.rdbluetooth.bean.SetParamsBean
import com.xsx.rdbluetooth.bean.event.ChangesDeviceEvent
import com.xsx.sdk.constant.WiFiMode
import com.xsx.sdk.listener.OnConnectBluetoothDeviceListener
import com.xsx.sdk.listener.OnLiveVideoListener
import com.xsx.sdk.listener.OnScanBluetoothDeviceListener
import com.xsx.sdk.main.DeviceMediaDownloadManager
import com.xsx.sdk.main.XSXSdk

/**
 * Thin wrapper around XSX AI Glass SDK (Bluetooth pair + Wi‑Fi live video + button params).
 */
class GlassesModule(
    private val context: Context,
    private val onDeviceFound: (name: String, address: String, rssi: Int) -> Unit,
    private val onConnectionChange: (state: String, name: String?, address: String?, detail: String?) -> Unit,
    private val onLiveVideoUrl: (url: String?) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private var initialized = false
    private var lastLiveUrl: String? = null

    val isReady: Boolean get() = initialized
    val liveVideoUrl: String? get() = lastLiveUrl

    fun init(application: Application, notificationActivityClass: String, appName: String, appIcon: Int): Boolean {
        return try {
            XSXSdk.getInstance()
                .setLog(application, true, false)
                .setShowToast(application, false)
                .init(
                    application,
                    /* applicationId */ "",
                    /* token */ "",
                    /* useAI */ true,
                    notificationActivityClass,
                    appName,
                    appIcon,
                )
            DeviceMediaDownloadManager.getInstance().init(application)
            DeviceMediaDownloadManager.getInstance().setOnLiveVideoListener(liveListener)
            XSXSdk.getInstance().addConnectBluetoothDeviceListener(connectListener)
            initialized = true
            true
        } catch (t: Throwable) {
            Log.e(TAG, "XSX init failed", t)
            initialized = false
            false
        }
    }

    fun startScan(): Boolean {
        if (!initialized) return false
        return try {
            XSXSdk.getInstance().startScanBluetoothDevice(scanListener)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "scan failed", t)
            false
        }
    }

    fun stopScan() {
        if (!initialized) return
        runCatching { XSXSdk.getInstance().stopScanBluetoothDevice() }
    }

    fun bind(name: String, address: String): Boolean {
        if (!initialized) return false
        return try {
            stopScan()
            XSXSdk.getInstance().bindDevice(name, address)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "bind failed", t)
            false
        }
    }

    fun disconnect() {
        if (!initialized) return
        runCatching { XSXSdk.getInstance().disconnect() }
    }

    fun unbind() {
        if (!initialized) return
        runCatching { XSXSdk.getInstance().unbindDevice() }
    }

    fun autoConnect() {
        if (!initialized) return
        runCatching { XSXSdk.getInstance().autoConnect() }
    }

    /** True when a glass is paired/connected (vendor: not null-or-unbind). */
    fun isBound(): Boolean {
        if (!initialized) return false
        return runCatching {
            !XSXSdk.getInstance().isDeviceEventNullOrUnbind()
        }.getOrDefault(false)
    }

    fun isAuthenticated(): Boolean = isBound()

    fun pullDeviceParams(): Boolean {
        if (!initialized) return false
        return runCatching { XSXSdk.getInstance().getDeviceParams() }.getOrDefault(false)
    }

    fun takePicture(): Boolean {
        if (!initialized) return false
        return runCatching { XSXSdk.getInstance().takePicture() }.getOrDefault(false)
    }

    /** Start glass camera stream over Wi‑Fi AP mode (same as vendor demo). */
    fun startLiveVideo(): Boolean {
        if (!initialized) return false
        return try {
            DeviceMediaDownloadManager.getInstance().setOnLiveVideoListener(liveListener)
            DeviceMediaDownloadManager.getInstance().startLiveVideo(WiFiMode.AP)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "startLiveVideo failed", t)
            false
        }
    }

    fun stopLiveVideo() {
        if (!initialized) return
        runCatching { DeviceMediaDownloadManager.getInstance().stopLiveVideo() }
        lastLiveUrl = null
        main.post { onLiveVideoUrl(null) }
    }

    /**
     * Apply a simplified left/right primary-button mapping.
     * [leftSingle]/[rightSingle] are Oriente action ids mapped to vendor function indices.
     */
    fun applyButtonMapping(
        leftSingle: String,
        leftDouble: String,
        leftLong: String,
        rightSingle: String,
        rightDouble: String,
        rightLong: String,
    ): Boolean {
        if (!initialized) return false
        return try {
            val bean = ButtonFunctionBean().apply {
                setHaveLeftButton1(true)
                setHaveRightButton1(true)
                setHaveLeftButton1SingleClick(true)
                setHaveLeftButton1DoubleClick(true)
                setHaveLeftButton1LongPress(true)
                setHaveRightButton1SingleClick(true)
                setHaveRightButton1DoubleClick(true)
                setHaveRightButton1LongPress(true)
                setLeftButton1SingleClickFuntion(toVendorFn(leftSingle))
                setLeftButton1DoubleClickFuntion(toVendorFn(leftDouble))
                setLeftButton1LongPressFuntion(toVendorFn(leftLong))
                setRightButton1SingleClickFuntion(toVendorFn(rightSingle))
                setRightButton1DoubleClickFuntion(toVendorFn(rightDouble))
                setRightButton1LongPressFuntion(toVendorFn(rightLong))
            }
            val params = SetParamsBean().apply {
                setHaveParam_ButtonFunction(true)
                setButtonFunctionBean(bean)
            }
            XSXSdk.getInstance().setDeviceParams(params)
        } catch (t: Throwable) {
            Log.e(TAG, "applyButtonMapping failed", t)
            false
        }
    }

    fun statusMap(): Map<String, Any?> {
        return mapOf(
            "sdkReady" to initialized,
            "bound" to isBound(),
            "authenticated" to isAuthenticated(),
            "liveVideoUrl" to lastLiveUrl,
        )
    }

    fun release() {
        stopScan()
        stopLiveVideo()
        if (initialized) {
            runCatching { XSXSdk.getInstance().removeConnectBluetoothDeviceListener(connectListener) }
            runCatching { XSXSdk.getInstance().release() }
        }
        initialized = false
    }

    private val scanListener = OnScanBluetoothDeviceListener { device, _, rssi ->
        val name = device?.name ?: return@OnScanBluetoothDeviceListener
        val address = device.address ?: return@OnScanBluetoothDeviceListener
        if (name.isBlank() || address.isBlank()) return@OnScanBluetoothDeviceListener
        main.post { onDeviceFound(name, address, rssi) }
    }

    private val connectListener = OnConnectBluetoothDeviceListener { name, address, event ->
        val state = event?.bleStatus?.state?.toString() ?: "unknown"
        main.post {
            onConnectionChange(state, name, address, summarize(event))
            // After connect, pull glass config automatically.
            if (state.contains("ServicesDiscovered", ignoreCase = true) ||
                state.contains("Authenticated", ignoreCase = true)
            ) {
                runCatching { XSXSdk.getInstance().getDeviceParams() }
                runCatching { XSXSdk.getInstance().syncTime() }
            }
        }
    }

    private val liveListener = object : OnLiveVideoListener {
        override fun hotspotStartSuccess(p0: Int) {}
        override fun onConnected(p0: String?, p1: Int) {}
        override fun discoverHotspotTimeout(p0: Int) {
            main.post { onLiveVideoUrl(null) }
        }
        override fun discoverPeersTimeout(p0: Int) {
            main.post { onLiveVideoUrl(null) }
        }
        override fun onConnectTimeout(p0: Int) {
            main.post { onLiveVideoUrl(null) }
        }
        override fun onLiveVideo(url: String?) {
            lastLiveUrl = url
            main.post { onLiveVideoUrl(url) }
        }
        override fun exitLiveVideo() {
            lastLiveUrl = null
            main.post { onLiveVideoUrl(null) }
        }
    }

    private fun summarize(event: ChangesDeviceEvent?): String? {
        if (event == null) return null
        return runCatching {
            "state=${event.bleStatus?.state}"
        }.getOrNull()
    }

    companion object {
        private const val TAG = "GlassesModule"

        /** Vendor gesture list indices used by XSX demo KeySet. */
        fun toVendorFn(orienteAction: String): Int = when (orienteAction) {
            "photo" -> 2 // take_picture
            "audio" -> 3 // record_audio
            "video" -> 4 // record_video
            "listen" -> 0 // play/pause closest generic; voice assistant via app overlay
            "find" -> 2 // take picture → phone runs detection
            "cancel" -> 0
            else -> 0
        }
    }
}
