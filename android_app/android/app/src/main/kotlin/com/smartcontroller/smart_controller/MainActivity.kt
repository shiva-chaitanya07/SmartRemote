package com.shivachaitanya07.phoneremote

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val methods = "phone_remote/bluetooth_hid"
    private val events = "phone_remote/bluetooth_hid_events"
    private val permissionCode = 4701
    private var adapter: BluetoothAdapter? = null
    private var hid: BluetoothHidDevice? = null
    private var host: BluetoothDevice? = null
    private var sink: EventChannel.EventSink? = null
    private var pending: MethodChannel.Result? = null
    private var pendingStart: MethodChannel.Result? = null
    private var startTimeout: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var registered = false

    private val descriptor = byteArrayOf(
        // Relative mouse: buttons, X, Y, vertical wheel.
        0x05, 0x01, 0x09, 0x02, 0xA1.toByte(), 0x01, 0x85.toByte(), 0x01,
        0x09, 0x01, 0xA1.toByte(), 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03,
        0x15, 0x00, 0x25, 0x01, 0x95.toByte(), 0x03, 0x75, 0x01, 0x81.toByte(), 0x02,
        0x95.toByte(), 0x01, 0x75, 0x05, 0x81.toByte(), 0x01, 0x05, 0x01, 0x09, 0x30,
        0x09, 0x31, 0x09, 0x38, 0x15, 0x81.toByte(), 0x25, 0x7F, 0x75, 0x08,
        0x95.toByte(), 0x03, 0x81.toByte(), 0x06, 0xC0.toByte(), 0xC0.toByte(),
        // Keyboard: modifier byte, reserved byte, six key slots.
        0x05, 0x01, 0x09, 0x06, 0xA1.toByte(), 0x01, 0x85.toByte(), 0x02,
        0x05, 0x07, 0x19, 0xE0.toByte(), 0x29, 0xE7.toByte(), 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95.toByte(), 0x08, 0x81.toByte(), 0x02, 0x95.toByte(), 0x01,
        0x75, 0x08, 0x81.toByte(), 0x01, 0x95.toByte(), 0x06, 0x75, 0x08, 0x15, 0x00,
        0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81.toByte(), 0x00,
        0xC0.toByte(),
        // Consumer media keys, 16-bit usage.
        0x05, 0x0C, 0x09, 0x01, 0xA1.toByte(), 0x01, 0x85.toByte(), 0x03,
        0x15, 0x00, 0x26, 0xFF.toByte(), 0x03, 0x19, 0x00, 0x2A, 0xFF.toByte(), 0x03,
        0x75, 0x10, 0x95.toByte(), 0x01, 0x81.toByte(), 0x00, 0xC0.toByte()
    )

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager)?.adapter
        MethodChannel(engine.dartExecutor.binaryMessenger, methods).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= 28 && adapter != null)
                "start" -> startHid(result)
                "bondedDevices" -> {
                    if (!hasPermissions()) { askPermissions(result); return@setMethodCallHandler }
                    result.success(try {
                        adapter?.bondedDevices?.map { mapOf("name" to safeName(it), "address" to it.address) } ?: emptyList<Map<String, String>>()
                    } catch (_: SecurityException) { emptyList<Map<String, String>>() })
                }
                "connect" -> connect(call.argument<String>("address"), result)
                "disconnect" -> {
                    try { host?.let { hid?.disconnect(it) }; result.success(true) }
                    catch (e: Exception) { result.error("DISCONNECT_FAILED", e.message, null) }
                }
                "send" -> result.success(sendEvent(call.argument<Map<String, Any>>("event") ?: emptyMap()))
                "stop" -> {
                    try { hid?.unregisterApp(); host = null; registered = false; result.success(true) }
                    catch (e: Exception) { result.error("STOP_FAILED", e.message, null) }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(engine.dartExecutor.binaryMessenger, events).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
    }

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(device: BluetoothDevice?, plugged: Boolean) {
            registered = plugged
            emit(mapOf("type" to "ready", "value" to plugged))
            val result = pendingStart ?: return
            pendingStart = null
            startTimeout?.let { mainHandler.removeCallbacks(it) }
            startTimeout = null
            if (plugged) {
                requestVisibilityOnlyWhenUnpaired()
                if (device != null && hid?.getConnectionState(device) == BluetoothProfile.STATE_CONNECTED) {
                    host = device
                    emit(mapOf("type" to "connection", "value" to "connected", "device" to safeName(device)))
                }
                result.success(true)
            } else {
                result.error("HID_NOT_READY", "Android did not register the HID profile. Keep Phone Remote open and try again.", null)
            }
        }
        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            if (state == BluetoothProfile.STATE_CONNECTED) host = device
            if (state == BluetoothProfile.STATE_DISCONNECTED && host == device) host = null
            val name = when (state) {
                BluetoothProfile.STATE_CONNECTED -> "connected"
                BluetoothProfile.STATE_CONNECTING -> "connecting"
                else -> "disconnected"
            }
            emit(mapOf("type" to "connection", "value" to name, "device" to safeName(device)))
        }
    }

    private fun startHid(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 28 || adapter == null) {
            result.error("UNSUPPORTED", "Bluetooth HID is not available on this phone.", null); return
        }
        if (!hasPermissions()) { askPermissions(result); return }
        if (adapter?.isEnabled != true) {
            result.error("BLUETOOTH_OFF", "Turn on Bluetooth in Android Settings, then try again.", null); return
        }
        if (hid != null && registered) { requestVisibilityOnlyWhenUnpaired(); result.success(true); return }
        if (hid != null) { registerHid(result); return }
        val accepted = adapter?.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                if (profile != BluetoothProfile.HID_DEVICE) return
                hid = proxy as BluetoothHidDevice
                registerHid(result)
            }
            override fun onServiceDisconnected(profile: Int) {
                hid = null; host = null; registered = false
                pendingStart?.error("HID_SERVICE_LOST", "Android Bluetooth HID service disconnected.", null)
                pendingStart = null
                startTimeout?.let { mainHandler.removeCallbacks(it) }; startTimeout = null
                emit(mapOf("type" to "connection", "value" to "disconnected"))
            }
        }, BluetoothProfile.HID_DEVICE)
        if (accepted != true) result.error("HID_UNAVAILABLE", "This phone does not expose the Bluetooth HID profile.", null)
    }

    private fun registerHid(result: MethodChannel.Result) {
        val profile = hid
        if (profile == null) {
            result.error("HID_UNAVAILABLE", "Android Bluetooth HID service is unavailable.", null)
            return
        }
        val sdp = BluetoothHidDeviceAppSdpSettings(
            "Phone Remote", "Keyboard and mouse remote", "Phone Remote",
            BluetoothHidDevice.SUBCLASS1_COMBO, descriptor
        )
        pendingStart = result
        try {
            val accepted = profile.registerApp(sdp, null, null, Executor { command -> mainHandler.post(command) }, callback)
            if (!accepted) {
                pendingStart = null
                result.error("HID_REGISTER_FAILED", "Android rejected the HID registration request. This phone's Bluetooth firmware may not support HID Device mode.", null)
                return
            }
            val timeout = Runnable {
                pendingStart?.let {
                    pendingStart = null
                    it.error("HID_REGISTER_TIMEOUT", "Android did not confirm HID readiness. Toggle Bluetooth off and on, keep Phone Remote open, then retry.", null)
                }
            }
            startTimeout?.let { mainHandler.removeCallbacks(it) }
            startTimeout = timeout
            mainHandler.postDelayed(timeout, 10000)
        } catch (e: Exception) {
            pendingStart = null
            result.error("HID_REGISTER_FAILED", e.message ?: "Android could not register Bluetooth HID.", null)
        }
    }
    private fun requestVisibilityOnlyWhenUnpaired() {
        val hasBondedDevice = try { adapter?.bondedDevices?.isNotEmpty() == true }
        catch (_: SecurityException) { true }
        if (!hasBondedDevice) makeDiscoverable()
    }

    private fun makeDiscoverable() {
        try {
            startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300))
        } catch (e: Exception) { emit(mapOf("type" to "error", "value" to ("Could not enable visibility: " + e.message))) }
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        if (!hasPermissions()) { askPermissions(result); return }
        if (!registered || hid == null) { result.error("HID_NOT_READY", "Wait until Bluetooth HID is ready, then try again.", null); return }
        try {
            val device = address?.let { adapter?.getRemoteDevice(it) }
            if (device == null) {
                result.error("CONNECT_FAILED", "The selected Bluetooth device address is invalid. Refresh the paired-device list and try again.", null)
                return
            }
            if (device.bondState != BluetoothDevice.BOND_BONDED) {
                result.error("DEVICE_NOT_PAIRED", "This laptop is not paired with the phone. Pair it from Windows Bluetooth Settings, then refresh this list.", null)
                return
            }
            if (hid?.connect(device) == true) result.success(true)
            else result.error("HID_CONNECT_REJECTED", "Android rejected the HID connection request even though this laptop is paired. Re-enable HID, then remove and pair the phone again in Windows Bluetooth Settings if it still fails.", null)
        } catch (e: Exception) { result.error("CONNECT_FAILED", e.message, null) }
    }

    private fun hasPermissions() = Build.VERSION.SDK_INT < 31 ||
        (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED)

    private fun askPermissions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 31) { result.error("PERMISSION_DENIED", "Bluetooth permission is unavailable.", null); return }
        pending = result
        requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE), permissionCode)
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code != permissionCode) return
        val result = pending ?: return
        pending = null
        if (grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED }) startHid(result)
        else result.error("PERMISSION_DENIED", "Bluetooth permissions are required for HID mode.", null)
    }

    private fun sendEvent(event: Map<String, Any>): Boolean {
        if (host == null) return false
        return try {
            when (event["type"]) {
                "key", "key_tap" -> key(event["key"] as? String ?: return false)
                "text" -> { (event["text"] as? String ?: return false).take(500).forEach { character(it) }; true }
                "mouse_move" -> mouse(0, bounded(event["dx"]), bounded(event["dy"]), 0)
                "mouse_scroll" -> mouse(0, 0, 0, -bounded(event["dy"]))
                "mouse_click" -> {
                    val button = when (event["button"]) { "left" -> 1; "right" -> 2; "middle" -> 4; else -> return false }
                    mouse(button, 0, 0, 0); mouse(0, 0, 0, 0)
                }
                "media" -> media(when (event["action"]) {
                    "play_pause" -> 0x00CD; "volume_up" -> 0x00E9; "volume_down" -> 0x00EA
                    "volume_mute" -> 0x00E2; else -> return false
                })
                else -> false
            }
        } catch (_: Exception) { false }
    }

    private fun bounded(value: Any?): Int = ((value as? Number)?.toDouble()?.roundToInt() ?: 0).coerceIn(-127, 127)
    private fun report(id: Int, bytes: ByteArray) = try { host?.let { hid?.sendReport(it, id, bytes) } == true } catch (_: Exception) { false }
    private fun mouse(buttons: Int, x: Int, y: Int, wheel: Int) =
        report(1, byteArrayOf(buttons.toByte(), x.toByte(), y.toByte(), wheel.toByte()))

    private fun key(value: String): Boolean {
        val k = value.lowercase()
        var mod = 0
        val symbols = mapOf(
            '-' to Pair(0, 0x2D), '_' to Pair(2, 0x2D), '=' to Pair(0, 0x2E), '+' to Pair(2, 0x2E),
            '[' to Pair(0, 0x2F), '{' to Pair(2, 0x2F), ']' to Pair(0, 0x30), '}' to Pair(2, 0x30),
            '\\' to Pair(0, 0x31), '|' to Pair(2, 0x31), ';' to Pair(0, 0x33), ':' to Pair(2, 0x33),
            '\'' to Pair(0, 0x34), '"' to Pair(2, 0x34), '\u0060' to Pair(0, 0x35), '~' to Pair(2, 0x35),
            ',' to Pair(0, 0x36), '<' to Pair(2, 0x36), '.' to Pair(0, 0x37), '>' to Pair(2, 0x37),
            '/' to Pair(0, 0x38), '?' to Pair(2, 0x38), '!' to Pair(2, 0x1E), '@' to Pair(2, 0x1F),
            '#' to Pair(2, 0x20), '$' to Pair(2, 0x21), '%' to Pair(2, 0x22), '^' to Pair(2, 0x23),
            '&' to Pair(2, 0x24), '*' to Pair(2, 0x25), '(' to Pair(2, 0x26), ')' to Pair(2, 0x27)
        )
        val code = when {
            k.length == 1 && k[0] in 'a'..'z' -> {
                if (value[0].isUpperCase()) mod = 2
                0x04 + (k[0] - 'a')
            }
            k.length == 1 && k[0] in '1'..'9' -> 0x1E + (k[0] - '1')
            k == "0" -> 0x27
            value.length == 1 && symbols.containsKey(value[0]) -> {
                val symbol = symbols.getValue(value[0])
                mod = symbol.first
                symbol.second
            }
            k in listOf("shift", "shift_l", "shift_r") -> { mod = 2; 0 }
            k == "ctrl" || k == "ctrl_l" -> { mod = 1; 0 }
            k == "ctrl_r" -> { mod = 16; 0 }
            k == "alt" || k == "alt_l" -> { mod = 4; 0 }
            k == "alt_r" -> { mod = 64; 0 }
            k == "enter" || k == "return" -> 0x28
            k == "esc" || k == "escape" -> 0x29
            k == "backspace" -> 0x2A
            k == "tab" -> 0x2B
            k == "space" -> 0x2C
            k == "caps_lock" -> 0x39
            k == "home" -> 0x4A
            k == "page_up" -> 0x4B
            k == "delete" -> 0x4C
            k == "end" -> 0x4D
            k == "page_down" -> 0x4E
            k == "right" -> 0x4F
            k == "left" -> 0x50
            k == "down" -> 0x51
            k == "up" -> 0x52
            else -> return false
        }
        val down = report(2, byteArrayOf(mod.toByte(), 0, code.toByte(), 0, 0, 0, 0, 0))
        report(2, ByteArray(8))
        return down
    }

    private fun character(c: Char) {
        val pair = when (c) {
            in 'A'..'Z' -> Pair(2, 0x04 + (c.lowercaseChar() - 'a'))
            in 'a'..'z' -> Pair(0, 0x04 + (c - 'a'))
            in '1'..'9' -> Pair(0, 0x1E + (c - '1'))
            '0' -> Pair(0, 0x27); ' ' -> Pair(0, 0x2C); '\n', '\r' -> Pair(0, 0x28)
            else -> return
        }
        report(2, byteArrayOf(pair.first.toByte(), 0, pair.second.toByte(), 0, 0, 0, 0, 0))
        report(2, ByteArray(8))
    }

    private fun media(usage: Int): Boolean {
        val ok = report(3, byteArrayOf((usage and 255).toByte(), (usage shr 8).toByte()))
        report(3, byteArrayOf(0, 0))
        return ok
    }

    private fun safeName(device: BluetoothDevice): String =
        try { device.name ?: "Bluetooth device" } catch (_: SecurityException) { "Bluetooth device" }

    private fun emit(value: Map<String, Any?>) { runOnUiThread { sink?.success(value) } }

    override fun onDestroy() {
        try { hid?.unregisterApp() } catch (_: Exception) {}
        try { adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hid) } catch (_: Exception) {}
        super.onDestroy()
    }
}
