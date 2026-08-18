package com.example.cycleone

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

class MainActivity : FlutterActivity() {

    private val CHANNEL = "cycleone/esp_wifi"
    private val TAG = "CycleOneNative"

    private val ESP_SSID = "CycleOneS1"
    private val ESP_PASSWORD = "CycleOne"
    private val ESP_IP = "10.10.10.10"
    private val ESP_PORT = 80

    private val U_RESPONSE_SIZE = 41
    private val T_RESPONSE_SIZE = 41
    private val TOKEN_SIZE = 40
    private val STATUS_RESPONSE_SIZE = 2

    private var wifiManager: WifiManager? = null
    private var connectivityManager: ConnectivityManager? = null
    private var currentSocket: Socket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var boundNetwork: Network? = null // ✅ remember the ESP network so we can reconnect on it

    private val socketLock = Any()
    private val commandLock = Any()
    private var connectionResultSent = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        connectivityManager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectToEsp" -> {
                    if (!checkPermissions()) {
                        result.error("PERMISSION_DENIED", "Location permission required", null)
                        return@setMethodCallHandler
                    }
                    connectToEsp(call, result)
                }
                "disconnectFromEsp" -> disconnectFromEsp(result)
                "getConnectionStatus" -> getConnectionStatus(result)
                "sendU" -> sendU(result)
                "sendT" -> sendT(call, result)
                "getStatus" -> getStatus(result)
                else -> result.notImplemented()
            }
        }

        Log.d(TAG, "================================")
        Log.d(TAG, "🚀 CycleOne Native Ready")
        Log.d(TAG, "📡 SSID: $ESP_SSID")
        Log.d(TAG, "🌐 ESP: $ESP_IP:$ESP_PORT")
        Log.d(TAG, "📱 Android Version: ${Build.VERSION.SDK_INT}")
        Log.d(TAG, "================================")
    }

    private fun checkPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val permissions = mutableListOf<String>()

            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.ACCESS_BACKGROUND_LOCATION
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                permissions.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            }

            if (permissions.isNotEmpty()) {
                ActivityCompat.requestPermissions(
                    this,
                    permissions.toTypedArray(),
                    1001
                )
                return false
            }
        }
        return true
    }

    // ============================================================
    // CONNECT TO ESP
    // ============================================================

    private fun connectToEsp(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectToEspAndroid10Plus(result)
            return
        }
        connectToEspOldAndroid(result)
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun connectToEspAndroid10Plus(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "================================")
            Log.d(TAG, "🔗 Android 10+: Connecting to ESP")
            Log.d(TAG, "📡 SSID: $ESP_SSID")
            Log.d(TAG, "🌐 $ESP_IP:$ESP_PORT")
            Log.d(TAG, "================================")

            closeSocket()
            connectionResultSent = false

            Log.d(TAG, "📡 Android 10+: Building NetworkSpecifier...")

            val networkSpecifier = android.net.wifi.WifiNetworkSpecifier.Builder()
                .setSsid(ESP_SSID)
                .setWpa2Passphrase(ESP_PASSWORD)
                .build()

            val networkRequest = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .setNetworkSpecifier(networkSpecifier)
                .build()

            unregisterNetworkCallback()

            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    Log.d(TAG, "✅ Android 10+: WiFi Network available!")
                    boundNetwork = network // ✅ keep a handle so sendU/sendT can reconnect fresh
                    if (!connectionResultSent) {
                        connectionResultSent = true
                        connectSocketWithNetwork(network, result)
                    }
                }

                override fun onUnavailable() {
                    Log.e(TAG, "❌ Android 10+: Network unavailable")
                    if (!connectionResultSent) {
                        connectionResultSent = true
                        handler.post {
                            result.error("WIFI_UNAVAILABLE", "ESP WiFi unavailable. Make sure ESP is powered ON.", null)
                        }
                    }
                }

                override fun onLost(network: Network) {
                    Log.w(TAG, "⚠️ Android 10+: Network lost")
                    closeSocket()
                    boundNetwork = null
                    unregisterNetworkCallback()
                }
            }

            connectivityManager?.requestNetwork(networkRequest, networkCallback!!)
            Log.d(TAG, "📡 Network request sent, waiting for connection...")

            handler.postDelayed({
                if (!connectionResultSent && !isSocketAlive()) {
                    connectionResultSent = true
                    Log.e(TAG, "⏰ Android 10+: Connection timeout")
                    unregisterNetworkCallback()
                    handler.post {
                        result.error("WIFI_TIMEOUT",
                            "Connection timeout. Make sure ESP is powered ON and in range.",
                            null)
                    }
                }
            }, 25000)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Android 10+ connection error", e)
            if (!connectionResultSent) {
                connectionResultSent = true
                handler.post {
                    result.error("WIFI_ERROR", e.message ?: "Connection failed", null)
                }
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun connectSocketWithNetwork(network: Network, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔌 Creating ESP TCP socket with network binding...")

            val socket = Socket()
            network.bindSocket(socket)
            socket.connect(InetSocketAddress(ESP_IP, ESP_PORT), 5000)
            socket.soTimeout = 5000
            socket.keepAlive = true
            socket.tcpNoDelay = true
            socket.setSoLinger(true, 0)

            currentSocket = socket
            input = socket.getInputStream()
            output = socket.getOutputStream()

            Log.d(TAG, "================================")
            Log.d(TAG, "✅ TCP SOCKET CONNECTED")
            Log.d(TAG, "🌐 $ESP_IP:$ESP_PORT")
            Log.d(TAG, "================================")

            handler.post {
                result.success(true)
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Socket creation failed", e)
            closeSocket()
            handler.post {
                result.error("SOCKET_ERROR", e.message ?: "Socket connection failed", null)
            }
        }
    }

    private fun connectToEspOldAndroid(result: MethodChannel.Result) {
        Thread {
            try {
                Log.d(TAG, "================================")
                Log.d(TAG, "🔗 Android 9-: Connecting to ESP")
                Log.d(TAG, "📡 SSID: $ESP_SSID")
                Log.d(TAG, "🌐 $ESP_IP:$ESP_PORT")
                Log.d(TAG, "================================")

                closeSocket()

                if (!wifiManager!!.isWifiEnabled) {
                    Log.e(TAG, "❌ WiFi is disabled")
                    handler.post {
                        result.error("WIFI_DISABLED", "WiFi is disabled", null)
                    }
                    return@Thread
                }

                val currentWifi = wifiManager!!.connectionInfo
                if (currentWifi != null && currentWifi.ssid == "\"$ESP_SSID\"") {
                    Log.d(TAG, "✅ Already connected to ESP WiFi")
                    connectSocket(result)
                    return@Thread
                }

                val existingNetworks = wifiManager!!.configuredNetworks
                for (network in existingNetworks) {
                    if (network.SSID == "\"$ESP_SSID\"") {
                        wifiManager!!.removeNetwork(network.networkId)
                        wifiManager!!.saveConfiguration()
                    }
                }

                val config = WifiConfiguration()
                config.SSID = "\"$ESP_SSID\""
                config.preSharedKey = "\"$ESP_PASSWORD\""
                config.status = WifiConfiguration.Status.ENABLED

                config.allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
                config.allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                config.allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                config.allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
                config.allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                config.allowedProtocols.set(WifiConfiguration.Protocol.WPA)

                val networkId = wifiManager!!.addNetwork(config)
                if (networkId == -1) {
                    Log.e(TAG, "❌ Failed to add WiFi network")
                    handler.post {
                        result.error("WIFI_ADD_FAILED", "Failed to add WiFi network", null)
                    }
                    return@Thread
                }

                Log.d(TAG, "✅ Network added with ID: $networkId")
                wifiManager!!.disconnect()
                wifiManager!!.enableNetwork(networkId, true)
                wifiManager!!.reconnect()

                var attempts = 0
                while (attempts < 30) {
                    Thread.sleep(500)
                    val info = wifiManager!!.connectionInfo
                    if (info != null && info.ssid == "\"$ESP_SSID\"") {
                        Log.d(TAG, "✅ Connected to ESP WiFi")
                        connectSocket(result)
                        return@Thread
                    }
                    attempts++
                }

                Log.e(TAG, "❌ Failed to connect to ESP WiFi (timeout)")
                handler.post {
                    result.error("WIFI_CONNECT_TIMEOUT", "Failed to connect to ESP WiFi", null)
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Connection error", e)
                handler.post {
                    result.error("CONNECTION_ERROR", e.message ?: "Connection failed", null)
                }
            }
        }.start()
    }

    private fun connectSocket(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔌 Creating ESP TCP socket...")

            val socket = Socket()
            socket.connect(InetSocketAddress(ESP_IP, ESP_PORT), 5000)
            socket.soTimeout = 5000
            socket.keepAlive = true
            socket.tcpNoDelay = true
            socket.setSoLinger(true, 0)

            currentSocket = socket
            input = socket.getInputStream()
            output = socket.getOutputStream()

            Log.d(TAG, "================================")
            Log.d(TAG, "✅ TCP SOCKET CONNECTED")
            Log.d(TAG, "🌐 $ESP_IP:$ESP_PORT")
            Log.d(TAG, "================================")

            handler.post {
                result.success(true)
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Socket creation failed", e)
            closeSocket()
            handler.post {
                result.error("SOCKET_ERROR", e.message ?: "Socket connection failed", null)
            }
        }
    }

    // ============================================================
    // ✅ SEND U — FIXED: close + reconnect fresh between failed attempts
    // ============================================================

    private fun sendU(result: MethodChannel.Result) {
        Thread {
            synchronized(commandLock) {
                try {
                    Log.d(TAG, "================================")
                    Log.d(TAG, "📤 SEND U")
                    Log.d(TAG, "================================")

                    var tokenList: List<Int>? = null
                    var attempts = 0
                    val maxAttempts = 4 // ✅ one extra attempt, since fresh connects are cheap

                    while (attempts < maxAttempts && tokenList == null) {
                        attempts++
                        Log.d(TAG, "🔄 Attempt $attempts/$maxAttempts")

                        // ✅ FIX: on every retry (not just the first), make sure we have a
                        // socket the ESP hasn't already silently dropped. isSocketAlive()
                        // only reflects LOCAL TCP state — it can't see that the ESP's
                        // WiFiClient already went out of scope and reset the connection.
                        if (!isSocketAlive()) {
                            Log.d(TAG, "🔌 Socket not alive, reconnecting...")
                            closeSocket()
                            Thread.sleep(100)
                            if (!reconnectTcp()) {
                                Log.e(TAG, "❌ Failed to connect")
                                Thread.sleep(200)
                                continue
                            }
                        } else {
                            Log.d(TAG, "✅ Using existing connection")
                        }

                        val socketInput = input
                        val socketOutput = output

                        if (socketInput == null || socketOutput == null) {
                            Log.e(TAG, "❌ Streams null")
                            closeSocket()
                            Thread.sleep(200)
                            continue
                        }

                        try {
                            while (socketInput.available() > 0) {
                                socketInput.read()
                            }
                            Log.d(TAG, "🧹 Buffer cleared")
                        } catch (_: Exception) {}

                        var readFailed = false

                        try {
                            Log.d(TAG, "📤 Sending 'U' command...")
                            socketOutput.write('U'.code)
                            socketOutput.flush()
                            Log.d(TAG, "✅ 'U' command sent")

                            Log.d(TAG, "📥 Reading 41 bytes...")
                            val response = readExactFast(socketInput, U_RESPONSE_SIZE, 2000)

                            if (response != null && response.isNotEmpty()) {
                                Log.d(TAG, "📥 Response size: ${response.size} bytes")

                                if (response.size == U_RESPONSE_SIZE) {
                                    val status = response[0].toInt() and 0xFF
                                    Log.d(TAG, "📥 ESP status byte: $status")

                                    if (status == 0) {
                                        val tokenBytes = response.copyOfRange(1, response.size)
                                        tokenList = tokenBytes.map { it.toInt() and 0xFF }
                                        Log.d(TAG, "✅ Token received: ${tokenList.size} bytes")
                                    } else {
                                        Log.e(TAG, "❌ ESP error status: $status")
                                        readFailed = true
                                    }
                                } else if (response.size == TOKEN_SIZE) {
                                    tokenList = response.map { it.toInt() and 0xFF }
                                    Log.d(TAG, "✅ Token received (no status): ${tokenList.size} bytes")
                                } else {
                                    Log.e(TAG, "❌ Unexpected response size: ${response.size}")
                                    readFailed = true
                                }
                            } else {
                                // ✅ This is the case from your log: EOF / 0 bytes.
                                // The ESP has already reset the connection.
                                Log.e(TAG, "❌ Empty response — ESP likely dropped the connection")
                                readFailed = true
                            }
                        } catch (e: Exception) {
                            // ✅ This is the "Broken pipe" case from your log.
                            Log.e(TAG, "❌ Write/Read error: ${e.message}")
                            readFailed = true
                        }

                        // ✅ THE ACTUAL FIX: whenever this attempt failed, force-close the
                        // socket now so the NEXT loop iteration's isSocketAlive() check
                        // correctly returns false and triggers a real reconnectTcp(),
                        // instead of retrying on a connection the ESP already killed.
                        if (readFailed || tokenList == null) {
                            closeSocket()
                        }

                        if (tokenList == null && attempts < maxAttempts) {
                            Log.d(TAG, "⏳ Retrying in 300ms...")
                            Thread.sleep(300)
                        }
                    }

                    if (tokenList == null) {
                        Log.e(TAG, "❌ Failed to get token after $maxAttempts attempts")
                        closeSocket()
                        handler.post {
                            result.error("ESP_U_RESPONSE_ERROR", "Failed to get token after retries", null)
                        }
                        return@synchronized
                    }

                    handler.post {
                        result.success(tokenList)
                    }

                } catch (e: Exception) {
                    Log.e(TAG, "❌ U error", e)
                    closeSocket()
                    handler.post {
                        result.error("ESP_U_ERROR", e.message ?: "U failed", null)
                    }
                }
            }
        }.start()
    }

    // ============================================================
    // ✅ SEND T — FIXED: same reconnect-on-failure pattern
    // ============================================================

    private fun sendT(call: MethodCall, result: MethodChannel.Result) {
        Thread {
            synchronized(commandLock) {
                try {
                    Log.d(TAG, "================================")
                    Log.d(TAG, "📤 SEND T")
                    Log.d(TAG, "================================")

                    val tokenList = call.argument<List<Int>>("token")
                    if (tokenList == null || tokenList.size != TOKEN_SIZE) {
                        handler.post {
                            result.error("INVALID_TOKEN", "Token must contain exactly 40 bytes", null)
                        }
                        return@synchronized
                    }

                    val token = ByteArray(TOKEN_SIZE)
                    for (i in 0 until TOKEN_SIZE) {
                        token[i] = tokenList[i].toByte()
                    }

                    var response: ByteArray? = null
                    var attempts = 0
                    val maxAttempts = 4 // ✅ one extra attempt

                    while (attempts < maxAttempts && response == null) {
                        attempts++
                        Log.d(TAG, "🔄 T attempt $attempts/$maxAttempts")

                        // ✅ FIX: same as sendU — always verify + rebuild the connection
                        // rather than trusting a socket that "looks" alive locally.
                        if (!isSocketAlive()) {
                            Log.d(TAG, "🔌 Socket not alive, reconnecting...")
                            closeSocket()
                            Thread.sleep(100)
                            if (!reconnectTcp()) {
                                Log.e(TAG, "❌ Failed to reconnect")
                                Thread.sleep(200)
                                continue
                            }
                        } else {
                            Log.d(TAG, "✅ Using existing connection for T")
                        }

                        val socketInput = input
                        val socketOutput = output

                        if (socketInput == null || socketOutput == null) {
                            closeSocket()
                            Thread.sleep(200)
                            continue
                        }

                        try {
                            while (socketInput.available() > 0) {
                                socketInput.read()
                            }
                            Log.d(TAG, "🧹 Buffer cleared")
                        } catch (_: Exception) {}

                        try {
                            // ✅ FIX: send 'T' + the 40-byte token as ONE write, not two.
                            // The ESP's handleTrigger() does a single non-blocking
                            // client->read(req, 40) with no retry loop — if the token
                            // arrives in a separate TCP segment after 'T' (as the old
                            // write+sleep(50)+write did), the ESP reads fewer than 40
                            // bytes and returns "Invalid data length" (status 1, 21
                            // bytes) — exactly what showed up in the logs. Combining
                            // into one write (with tcpNoDelay already set) sends both
                            // in a single packet so the ESP gets all 41 bytes together.
                            val payload = ByteArray(1 + TOKEN_SIZE)
                            payload[0] = 'T'.code.toByte()
                            System.arraycopy(token, 0, payload, 1, TOKEN_SIZE)

                            Log.d(TAG, "📤 Writing 'T' + 40-byte token as one packet")
                            socketOutput.write(payload)
                            socketOutput.flush()
                            Log.d(TAG, "✅ T + 40 bytes sent")

                            response = readExactFast(socketInput, T_RESPONSE_SIZE, 3000)

                            if (response == null) {
                                Log.e(TAG, "❌ No T response — ESP likely dropped the connection")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Write/Read error: ${e.message}")
                            response = null
                        }

                        // ✅ THE ACTUAL FIX: force-close on failure so the next attempt
                        // reconnects for real instead of reusing a dead socket.
                        if (response == null) {
                            closeSocket()
                            if (attempts < maxAttempts) {
                                Thread.sleep(200)
                            }
                        }
                    }

                    if (response == null) {
                        Log.e(TAG, "❌ No T response from ESP after $maxAttempts attempts")
                        closeSocket()
                        handler.post {
                            result.error("ESP_T_RESPONSE_ERROR", "ESP did not return T response", null)
                        }
                        return@synchronized
                    }

                    Log.d(TAG, "✅ T response received: ${response.size} bytes")

                    val status = if (response.size >= 1) {
                        response[0].toInt() and 0xFF
                    } else {
                        -1
                    }
                    Log.d(TAG, "📥 T status: $status")

                    if (status == 0) {
                        Log.d(TAG, "================================")
                        Log.d(TAG, "✅ T COMMAND SUCCESS")
                        Log.d(TAG, "================================")
                        handler.post { result.success(true) }
                    } else if (status == -1) {
                        Log.d(TAG, "⚠️ No status byte, assuming success")
                        handler.post { result.success(true) }
                    } else {
                        Log.e(TAG, "❌ ESP returned error status: $status")
                        handler.post { result.success(false) }
                    }

                } catch (e: Exception) {
                    Log.e(TAG, "❌ T error", e)
                    closeSocket()
                    handler.post {
                        result.error("ESP_T_ERROR", e.message ?: "T command failed", null)
                    }
                }
            }
        }.start()
    }

    // ============================================================
    // GET STATUS — same fix applied
    // ============================================================

    private fun getStatus(result: MethodChannel.Result) {
        Thread {
            synchronized(commandLock) {
                try {
                    var response: ByteArray? = null
                    var attempts = 0
                    val maxAttempts = 3

                    while (attempts < maxAttempts && response == null) {
                        attempts++

                        if (!isSocketAlive()) {
                            closeSocket()
                            if (!reconnectTcp()) {
                                Thread.sleep(200)
                                continue
                            }
                        }

                        val socketInput = input
                        val socketOutput = output

                        if (socketInput == null || socketOutput == null) {
                            closeSocket()
                            continue
                        }

                        try {
                            while (socketInput.available() > 0) {
                                socketInput.read()
                            }
                        } catch (_: Exception) {}

                        try {
                            socketOutput.write('S'.code)
                            socketOutput.flush()
                            response = readExactFast(socketInput, STATUS_RESPONSE_SIZE, 3000)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Status write/read error: ${e.message}")
                            response = null
                        }

                        // ✅ FIX: close on failure so next attempt reconnects for real
                        if (response == null || response.size < 2) {
                            closeSocket()
                            response = null
                            if (attempts < maxAttempts) Thread.sleep(200)
                        }
                    }

                    if (response == null || response.size < 2) {
                        closeSocket()
                        handler.post {
                            result.error("ESP_STATUS_ERROR", "Status response failed", null)
                        }
                        return@synchronized
                    }

                    val state = response[1].toInt().and(0xFF)
                    Log.d(TAG, "📥 ESP state: ${if (state == 1) "UNLOCKED" else "LOCKED"} ($state)")
                    handler.post { result.success(state) }

                } catch (e: Exception) {
                    closeSocket()
                    handler.post {
                        result.error("ESP_STATUS_ERROR", e.message ?: "Status failed", null)
                    }
                }
            }
        }.start()
    }

    // ============================================================
    // UTILITY METHODS
    // ============================================================

    private fun readExactFast(input: InputStream, size: Int, timeoutMs: Long): ByteArray? {
        val buffer = ByteArray(size)
        var total = 0
        val start = System.currentTimeMillis()

        while (total < size) {
            if (System.currentTimeMillis() - start >= timeoutMs) {
                Log.e(TAG, "⏰ Fast read timeout: $total/$size")
                return if (total > 0) buffer.copyOf(total) else null
            }

            try {
                val count = input.read(buffer, total, size - total)

                if (count < 0) {
                    Log.d(TAG, "📥 EOF reached, read $total/$size bytes")
                    return if (total > 0) buffer.copyOf(total) else null
                }

                if (count > 0) {
                    total += count
                    Log.d(TAG, "📥 Read $total/$size bytes")
                } else {
                    Thread.sleep(5)
                }

            } catch (e: Exception) {
                if (total > 0) {
                    Log.d(TAG, "📥 Connection aborted, read $total/$size bytes")
                    return buffer.copyOf(total)
                }
                Log.e(TAG, "❌ Read error: ${e.message}")
                return null
            }
        }

        return buffer
    }

    private fun unregisterNetworkCallback() {
        try {
            networkCallback?.let {
                connectivityManager?.unregisterNetworkCallback(it)
            }
        } catch (_: Exception) {}
        networkCallback = null
    }

    private fun isSocketAlive(): Boolean {
        synchronized(socketLock) {
            val socket = currentSocket ?: return false
            return socket.isConnected && !socket.isClosed &&
                    !socket.isInputShutdown && !socket.isOutputShutdown
        }
    }

    // ✅ FIX: reconnect on the ESP's own WiFi network when we have it (Android 10+),
    // instead of a plain Socket() which won't route to the ESP AP correctly if the
    // phone also has a normal internet-connected WiFi/cellular network active.
    private fun reconnectTcp(): Boolean {
        synchronized(commandLock) {
            if (isSocketAlive()) {
                return true
            }

            closeSocket()

            return try {
                Log.d(TAG, "🔄 Reconnecting TCP socket...")
                val socket = Socket()

                val network = boundNetwork
                if (network != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    network.bindSocket(socket)
                }

                socket.connect(InetSocketAddress(ESP_IP, ESP_PORT), 5000)
                socket.soTimeout = 5000
                socket.keepAlive = true
                socket.tcpNoDelay = true
                socket.setSoLinger(true, 0)

                currentSocket = socket
                input = socket.getInputStream()
                output = socket.getOutputStream()

                Log.d(TAG, "✅ TCP reconnected")
                true
            } catch (e: Exception) {
                Log.e(TAG, "❌ TCP reconnect failed: ${e.message}")
                closeSocket()
                false
            }
        }
    }

    private fun getConnectionStatus(result: MethodChannel.Result) {
        result.success(isSocketAlive())
    }

    private fun disconnectFromEsp(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🔌 Disconnecting ESP")
            unregisterNetworkCallback()
            closeSocket()
            boundNetwork = null
            result.success(true)
        } catch (e: Exception) {
            result.error("ESP_DISCONNECT_ERROR", e.message, null)
        }
    }

    private fun closeSocket() {
        synchronized(socketLock) {
            try { input?.close() } catch (_: Exception) {}
            try { output?.close() } catch (_: Exception) {}
            try { currentSocket?.close() } catch (_: Exception) {}
            input = null
            output = null
            currentSocket = null
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "🧹 MainActivity destroy")
        unregisterNetworkCallback()
        closeSocket()
        super.onDestroy()
    }

    companion object {
        private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    }
}