package com.example.cycleone

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.MacAddress
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    // ============================================================
    // CHANNEL / ESP CONFIGURATION
    // ============================================================

    private val CHANNEL = "cycleone/esp_wifi"

    private val TAG = "CycleOneNative"

    // Defaults are used only when a legacy stand row omits optional endpoint
    // fields. The values supplied by Flutter are authoritative for every
    // connection, so two stands may safely share an SSID.
    private val DEFAULT_ESP_SSID = "CycleOneS1"
    private val DEFAULT_ESP_PASSWORD = "CycleOne"
    private val DEFAULT_ESP_IP = "10.10.10.10"
    private val DEFAULT_ESP_PORT = 80

    @Volatile private var espSsid = DEFAULT_ESP_SSID
    @Volatile private var espPassword = DEFAULT_ESP_PASSWORD
    @Volatile private var espIp = DEFAULT_ESP_IP
    @Volatile private var espPort = DEFAULT_ESP_PORT
    @Volatile private var expectedBssid: String? = null

    /*
     * ESP protocol sizes
     *
     * U:
     *   1 byte status
     *   40 byte token
     *   = 41 bytes
     *
     * T:
     *   1 byte status
     *   40 byte response
     *   = 41 bytes
     *
     * S:
     *   1 byte status
     *   1 byte lock state
     *   = 2 bytes
     *
     * P:
     *   1 byte status
     *   1 byte lock state
     *   1 byte physical cycle presence
     *   = 3 bytes
     */
    private val TOKEN_SIZE = 40

    private val U_RESPONSE_SIZE = 41

    private val T_RESPONSE_SIZE = 41

    private val STATUS_RESPONSE_SIZE = 2

    private val PRESENCE_RESPONSE_SIZE = 3

    // ============================================================
    // ANDROID SERVICES
    // ============================================================

    private var wifiManager: WifiManager? = null

    private var connectivityManager:
            ConnectivityManager? = null

    // ============================================================
    // SOCKET
    // ============================================================

    private var currentSocket: Socket? = null

    private var input: InputStream? = null

    private var output: OutputStream? = null

    /*
     * Android 10+ target WiFi network.
     *
     * This is important because the phone may still have
     * mobile data / another WiFi network as default.
     */
    private var boundNetwork: Network? = null

    private var networkCallback:
            ConnectivityManager.NetworkCallback? = null

    // ============================================================
    // LOCKS
    // ============================================================

    private val socketLock = Any()

    private val commandLock = Any()

    // ============================================================
    // CONNECTION STATE
    // ============================================================

    private val connectionResultSent =
        AtomicBoolean(false)

    // ============================================================
    // MAIN THREAD HANDLER
    // ============================================================

    private val handler =
        Handler(
            Looper.getMainLooper()
        )

    // ============================================================
    // FLUTTER ENGINE
    // ============================================================

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {

        super.configureFlutterEngine(
            flutterEngine
        )

        wifiManager =
            applicationContext
                .getSystemService(
                    Context.WIFI_SERVICE
                ) as WifiManager

        connectivityManager =
            applicationContext
                .getSystemService(
                    Context.CONNECTIVITY_SERVICE
                ) as ConnectivityManager

        MethodChannel(
            flutterEngine
                .dartExecutor
                .binaryMessenger,
            CHANNEL
        ).setMethodCallHandler {

                call,
                result ->

            when (call.method) {

                "connectToEsp" -> {

                    handleConnect(
                        call,
                        result
                    )
                }

                "disconnectFromEsp" -> {

                    disconnect(
                        result
                    )
                }

                "getConnectionStatus" -> {

                    result.success(
                        isSocketAlive()
                    )
                }

                "sendU" -> {

                    sendU(
                        result
                    )
                }

                "sendT" -> {

                    sendT(
                        call,
                        result
                    )
                }

                "getStatus" -> {

                    getStatus(
                        result
                    )
                }

                "getPresenceStatus" -> {

                    getPresenceStatus(
                        result
                    )
                }

                else -> {

                    result.notImplemented()
                }
            }
        }

        Log.d(
            TAG,
            "================================"
        )

        Log.d(
            TAG,
            "CycleOne native bridge ready"
        )

        Log.d(
            TAG,
            "SSID: $espSsid"
        )

        Log.d(
            TAG,
            "IP: $espIp"
        )

        Log.d(
            TAG,
            "PORT: $espPort"
        )

        Log.d(
            TAG,
            "================================"
        )
    }

    // ============================================================
    // PERMISSION
    // ============================================================

    private fun hasLocationPermission():
            Boolean {

        return if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.M
        ) {

            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) ==
                    PackageManager.PERMISSION_GRANTED

        } else {

            true
        }
    }

    private fun requestLocationPermission():
            Boolean {

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.M
        ) {

            if (
                !hasLocationPermission()
            ) {

                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION
                    ),
                    1001
                )

                return false
            }
        }

        return true
    }

    // ============================================================
    // CONNECT ENTRY
    // ============================================================

    private fun handleConnect(
        call: MethodCall,
        result: MethodChannel.Result
    ) {

        if (
            !requestLocationPermission()
        ) {

            result.error(
                "PERMISSION_DENIED",
                "Location permission is required for WiFi connection.",
                null
            )

            return
        }

        val mac =
            call.argument<String>(
                "mac"
            )
                ?.trim()
                ?.uppercase()

        if (
            mac.isNullOrEmpty()
        ) {

            result.error(
                "INVALID_MAC",
                "ESP MAC is required.",
                null
            )

            return
        }

        /*
         * Validate MAC format before Android API.
         */
        if (
            !isValidMac(
                mac
            )
        ) {

            result.error(
                "INVALID_MAC",
                "Invalid ESP MAC: $mac",
                null
            )

            return
        }

        val requestedSsid = call.argument<String>("ssid")?.trim().orEmpty()
        val requestedPassword = call.argument<String>("password")?.trim().orEmpty()
        val requestedIp = call.argument<String>("ip")?.trim().orEmpty()
        val requestedPort = call.argument<Int>("port") ?: DEFAULT_ESP_PORT
        if (requestedSsid.isEmpty() || requestedPassword.isEmpty() || requestedIp.isEmpty() || requestedPort !in 1..65535) {
            result.error("INVALID_ENDPOINT", "The stand has an invalid ESP endpoint.", null)
            return
        }
        espSsid = requestedSsid
        espPassword = requestedPassword
        espIp = requestedIp
        espPort = requestedPort
        expectedBssid = mac

        Log.d(
            TAG,
            "================================"
        )

        Log.d(
            TAG,
            "Connecting to ESP"
        )

        Log.d(
            TAG,
            "SSID=$espSsid"
        )

        Log.d(
            TAG,
            "BSSID=$mac"
        )

        Log.d(
            TAG,
            "IP=$espIp"
        )

        Log.d(
            TAG,
            "================================"
        )

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.Q
        ) {

            connectAndroid10Plus(result)

        } else {

            connectOlderAndroid(result)
        }
    }

    // ============================================================
    // MAC VALIDATION
    // ============================================================

    private fun isValidMac(
        mac: String
    ): Boolean {

        return Regex(
            "^([0-9A-F]{2}:){5}[0-9A-F]{2}$"
        ).matches(
            mac.uppercase()
        )
    }

    // ============================================================
    // ANDROID 10+
    // ============================================================

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun connectAndroid10Plus(
        result: MethodChannel.Result
    ) {

        try {

            closeSocket()

            unregisterNetworkCallback()

            boundNetwork =
                null

            connectionResultSent.set(
                false
            )

            Log.d(
                TAG,
                "Creating WifiNetworkSpecifier"
            )

            val specifier =
                android.net.wifi
                    .WifiNetworkSpecifier
                    .Builder()
                    .setSsid(
                        espSsid
                    )
                    .setWpa2Passphrase(
                        espPassword
                    )
                    .setBssid(
                        MacAddress.fromString(expectedBssid!!)
                    )
                    .build()

            val request =
                NetworkRequest.Builder()
                    .addTransportType(
                        NetworkCapabilities
                            .TRANSPORT_WIFI
                    )
                    .setNetworkSpecifier(
                        specifier
                    )
                    .build()

            networkCallback =
                object :
                    ConnectivityManager
                    .NetworkCallback() {

                    override fun onAvailable(
                        network: Network
                    ) {

                        Log.d(
                            TAG,
                            "Target WiFi available"
                        )

                        boundNetwork =
                            network

                        if (
                            connectionResultSent
                                .compareAndSet(
                                    false,
                                    true
                                )
                        ) {

                            connectSocketUsingNetwork(
                                network,
                                result
                            )
                        }
                    }

                    override fun onUnavailable() {

                        Log.e(
                            TAG,
                            "Target ESP unavailable"
                        )

                        if (
                            connectionResultSent
                                .compareAndSet(
                                    false,
                                    true
                                )
                        ) {

                            unregisterNetworkCallback()

                            result.error(
                                "WIFI_UNAVAILABLE",
                                "Target ESP WiFi is unavailable.",
                                null
                            )
                        }
                    }

                    override fun onLost(
                        network: Network
                    ) {

                        Log.w(
                            TAG,
                            "ESP WiFi lost"
                        )

                        if (
                            boundNetwork ==
                            network
                        ) {

                            boundNetwork =
                                null
                        }

                        closeSocket()
                    }
                }

            connectivityManager
                ?.requestNetwork(
                    request,
                    networkCallback!!
                )

            /*
             * Connection timeout.
             */
            handler.postDelayed(
                {

                    if (
                        connectionResultSent
                            .compareAndSet(
                                false,
                                true
                            )
                    ) {

                        Log.e(
                            TAG,
                            "ESP WiFi connection timeout"
                        )

                        unregisterNetworkCallback()

                        result.error(
                            "WIFI_TIMEOUT",
                            "Target ESP was not found.",
                            null
                        )
                    }

                },
                25000
            )

        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "WiFi connection error",
                e
            )

            if (
                connectionResultSent
                    .compareAndSet(
                        false,
                        true
                    )
            ) {

                result.error(
                    "WIFI_ERROR",
                    e.message
                        ?: "WiFi connection error",
                    null
                )
            }
        }
    }

    // ============================================================
    // SOCKET USING TARGET NETWORK
    // ============================================================

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun connectSocketUsingNetwork(
        network: Network,
        result: MethodChannel.Result
    ) {

        Thread {

            try {

                val socket =
                    Socket()

                /*
                 * CRITICAL:
                 *
                 * Bind socket to the selected ESP network.
                 *
                 * This prevents Android from sending
                 * 10.10.10.10 through mobile/default network.
                 */
                network.bindSocket(
                    socket
                )

                socket.connect(
                    InetSocketAddress(
                        espIp,
                        espPort
                    ),
                    10000
                )

                socket.soTimeout =
                    10000

                socket.keepAlive =
                    true

                socket.tcpNoDelay =
                    true

                synchronized(
                    socketLock
                ) {

                    currentSocket =
                        socket

                    input =
                        socket.getInputStream()

                    output =
                        socket.getOutputStream()
                }

                Log.d(
                    TAG,
                    "TCP socket connected to $espIp:$espPort"
                )

                handler.post {

                    result.success(
                        true
                    )
                }

            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "Socket connection error",
                    e
                )

                closeSocket()

                handler.post {

                    result.error(
                        "SOCKET_ERROR",
                        e.message
                            ?: "Unable to connect TCP socket.",
                        null
                    )
                }
            }
        }.start()
    }

    // ============================================================
    // OLD ANDROID
    // ============================================================

    private fun connectOlderAndroid(result: MethodChannel.Result) {

        Thread {

            try {

                val manager =
                    wifiManager

                if (
                    manager == null ||
                    !manager.isWifiEnabled
                ) {

                    handler.post {

                        result.error(
                            "WIFI_DISABLED",
                            "WiFi is disabled.",
                            null
                        )
                    }

                    return@Thread
                }

                closeSocket()

                val info =
                    manager.connectionInfo

                if (
                    info != null &&
                    info.ssid == "\"$espSsid\""
                ) {

                    if (info.bssid?.uppercase() != expectedBssid) {
                        handler.post { result.error("BSSID_MISMATCH", "A different stand is already connected.", null) }
                        return@Thread
                    }

                    Log.d(
                        TAG,
                        "Already connected to $espSsid"
                    )

                    connectOldSocket(
                        result
                    )

                    return@Thread
                }

                val networks =
                    manager.configuredNetworks
                        ?: emptyList()

                for (
                network in networks
                ) {

                    if (network.SSID == "\"$espSsid\"") {

                        manager.removeNetwork(
                            network.networkId
                        )
                    }
                }

                val config =
                    WifiConfiguration()

                config.SSID =
                    "\"$espSsid\""

                config.preSharedKey =
                    "\"$espPassword\""

                config.allowedKeyManagement.set(
                    WifiConfiguration
                        .KeyMgmt.WPA_PSK
                )

                val networkId =
                    manager.addNetwork(
                        config
                    )

                if (
                    networkId < 0
                ) {

                    handler.post {

                        result.error(
                            "WIFI_ADD_FAILED",
                            "Could not configure ESP WiFi.",
                            null
                        )
                    }

                    return@Thread
                }

                manager.disconnect()

                manager.enableNetwork(
                    networkId,
                    true
                )

                manager.reconnect()

                var attempt = 0

                while (
                    attempt < 40
                ) {

                    Thread.sleep(
                        500
                    )

                    val current =
                        manager.connectionInfo

                    if (
                        current != null &&
                        current.ssid == "\"$espSsid\""
                    ) {

                        Log.d(
                            TAG,
                            "Connected to $espSsid"
                        )

                        val bssid = current.bssid?.uppercase()
                        if (bssid == null || bssid != expectedBssid) {
                            handler.post { result.error("BSSID_MISMATCH", "A different stand answered the Wi-Fi request.", null) }
                            return@Thread
                        }

                        connectOldSocket(
                            result
                        )

                        return@Thread
                    }

                    attempt++
                }

                handler.post {

                    result.error(
                        "WIFI_TIMEOUT",
                        "Could not connect to ESP WiFi.",
                        null
                    )
                }

            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "Old Android WiFi error",
                    e
                )

                handler.post {

                    result.error(
                        "WIFI_ERROR",
                        e.message
                            ?: "WiFi error",
                        null
                    )
                }
            }

        }.start()
    }

    // ============================================================
    // OLD ANDROID SOCKET
    // ============================================================

    private fun connectOldSocket(
        result: MethodChannel.Result
    ) {

        try {

            val socket =
                Socket()

            socket.connect(
                InetSocketAddress(espIp, espPort),
                10000
            )

            socket.soTimeout =
                10000

            socket.keepAlive =
                true

            socket.tcpNoDelay =
                true

            synchronized(
                socketLock
            ) {

                currentSocket =
                    socket

                input =
                    socket.getInputStream()

                output =
                    socket.getOutputStream()
            }

            Log.d(
                TAG,
                "Old Android TCP socket connected"
            )

            handler.post {

                result.success(
                    true
                )
            }

        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "Old Android socket error",
                e
            )

            closeSocket()

            handler.post {

                result.error(
                    "SOCKET_ERROR",
                    e.message
                        ?: "Socket connection failed.",
                    null
                )
            }
        }
    }

    // ============================================================
    // SEND U
    // ============================================================

    private fun sendU(
        result: MethodChannel.Result
    ) {

        Thread {

            synchronized(
                commandLock
            ) {

                try {

                    if (
                        !isSocketAlive()
                    ) {

                        Log.w(
                            TAG,
                            "Socket not alive. Reconnecting..."
                        )

                        if (
                            !reconnectTcp()
                        ) {

                            handler.post {

                                result.error(
                                    "ESP_CONNECTION",
                                    "ESP connection lost.",
                                    null
                                )
                            }

                            return@synchronized
                        }
                    }

                    val inputStream =
                        input

                    val outputStream =
                        output

                    if (
                        inputStream == null ||
                        outputStream == null
                    ) {

                        handler.post {

                            result.error(
                                "ESP_STREAM",
                                "ESP stream unavailable.",
                                null
                            )
                        }

                        return@synchronized
                    }

                    /*
                     * Remove only stale bytes that were already
                     * waiting before this command.
                     */
                    clearInput(
                        inputStream
                    )

                    Log.d(
                        TAG,
                        "Sending U command"
                    )

                    outputStream.write(
                        'U'.code
                    )

                    outputStream.flush()

                    /*
                     * ESP firmware:
                     *
                     * client.write(0);
                     * client.write(respArr, 40);
                     *
                     * TOTAL = 41 bytes
                     */
                    val response =
                        readExact(
                            inputStream,
                            U_RESPONSE_SIZE,
                            8000
                        )

                    if (
                        response == null ||
                        response.size !=
                        U_RESPONSE_SIZE
                    ) {

                        Log.e(
                            TAG,
                            "Invalid U response. Expected=$U_RESPONSE_SIZE"
                        )

                        handler.post {

                            result.error(
                                "ESP_U_RESPONSE",
                                "Invalid U response. Expected 41 bytes.",
                                null
                            )
                        }

                        return@synchronized
                    }

                    Log.d(
                        TAG,
                        "U response received: ${response.size} bytes"
                    )

                    val status =
                        response[0]
                            .toInt()
                            .and(0xFF)

                    Log.d(
                        TAG,
                        "U status byte=$status"
                    )

                    /*
                     * Flutter ESPLockService accepts:
                     *
                     * 41 bytes:
                     *   status + token
                     *
                     * or it can extract the 40-byte token.
                     *
                     * We return the complete 41-byte response
                     * because the Dart code already handles it.
                     */
                    handler.post {

                        result.success(
                            response.toList()
                        )
                    }

                } catch (
                    e: SocketTimeoutException
                ) {

                    Log.e(
                        TAG,
                        "U response timeout",
                        e
                    )

                    closeSocket()

                    handler.post {

                        result.error(
                            "ESP_U_TIMEOUT",
                            "ESP did not return a complete U response.",
                            null
                        )
                    }

                } catch (
                    e: Exception
                ) {

                    Log.e(
                        TAG,
                        "U command error",
                        e
                    )

                    closeSocket()

                    handler.post {

                        result.error(
                            "ESP_U_ERROR",
                            e.message
                                ?: "Unknown U error.",
                            null
                        )
                    }
                }
            }

        }.start()
    }

    // ============================================================
    // SEND T
    // ============================================================

    private fun sendT(
        call: MethodCall,
        result: MethodChannel.Result
    ) {

        Thread {

            synchronized(
                commandLock
            ) {

                try {

                    val token =
                        call.argument<List<Int>>(
                            "token"
                        )

                    if (
                        token == null ||
                        token.size !=
                        TOKEN_SIZE
                    ) {

                        handler.post {

                            result.error(
                                "INVALID_TOKEN",
                                "Token must be exactly 40 bytes.",
                                null
                            )
                        }

                        return@synchronized
                    }

                    if (
                        !isSocketAlive()
                    ) {

                        Log.w(
                            TAG,
                            "Socket not alive before T. Reconnecting..."
                        )

                        if (
                            !reconnectTcp()
                        ) {

                            handler.post {

                                result.error(
                                    "ESP_CONNECTION",
                                    "ESP connection lost.",
                                    null
                                )
                            }

                            return@synchronized
                        }
                    }

                    val inputStream =
                        input

                    val outputStream =
                        output

                    if (
                        inputStream == null ||
                        outputStream == null
                    ) {

                        handler.post {

                            result.error(
                                "ESP_STREAM",
                                "ESP stream unavailable.",
                                null
                            )
                        }

                        return@synchronized
                    }

                    clearInput(
                        inputStream
                    )

                    /*
                     * Packet:
                     *
                     * 1 byte  = T
                     * 40 bytes = transformed token
                     *
                     * TOTAL = 41 bytes
                     */
                    val packet =
                        ByteArray(
                            1 + TOKEN_SIZE
                        )

                    packet[0] =
                        'T'.code.toByte()

                    for (
                    i in 0 until TOKEN_SIZE
                    ) {

                        packet[i + 1] =
                            token[i].toByte()
                    }

                    Log.d(
                        TAG,
                        "Sending T command: ${packet.size} bytes"
                    )

                    outputStream.write(
                        packet
                    )

                    outputStream.flush()

                    /*
                     * ESP handleTrigger() eventually calls:
                     *
                     * sendStatusWithoutRfidPing()
                     *
                     * which returns:
                     *
                     * 1 status byte
                     * +
                     * 40 bytes
                     *
                     * = 41 bytes
                     */
                    val response =
                        readExact(
                            inputStream,
                            T_RESPONSE_SIZE,
                            8000
                        )

                    if (
                        response == null ||
                        response.size !=
                        T_RESPONSE_SIZE
                    ) {

                        Log.e(
                            TAG,
                            "Invalid T response"
                        )

                        // The relay may already have acted. Force a fresh
                        // socket so the Dart layer can perform a status-only
                        // recovery check; never reuse a desynchronised stream.
                        closeSocket()

                        handler.post {

                            result.error(
                                "ESP_T_RESPONSE",
                                "Invalid T response. Expected 41 bytes.",
                                null
                            )
                        }

                        return@synchronized
                    }

                    val status =
                        response[0]
                            .toInt()
                            .and(0xFF)

                    Log.d(
                        TAG,
                        "T response received: ${response.size} bytes"
                    )

                    Log.d(
                        TAG,
                        "T status=$status"
                    )

                    /*
                     * ESP status:
                     *
                     * 0 = success
                     * 1 = error
                     */
                    handler.post {

                        result.success(
                            status == 0
                        )
                    }

                } catch (
                    e: SocketTimeoutException
                ) {

                    Log.e(
                        TAG,
                        "T response timeout",
                        e
                    )

                    closeSocket()

                    handler.post {

                        result.error(
                            "ESP_T_TIMEOUT",
                            "ESP did not return a complete T response.",
                            null
                        )
                    }

                } catch (
                    e: Exception
                ) {

                    Log.e(
                        TAG,
                        "T command error",
                        e
                    )

                    closeSocket()

                    handler.post {

                        result.error(
                            "ESP_T_ERROR",
                            e.message
                                ?: "Unknown T error.",
                            null
                        )
                    }
                }
            }

        }.start()
    }

    // ============================================================
    // STATUS
    // ============================================================

    private fun getStatus(
        result: MethodChannel.Result
    ) {

        Thread {

            synchronized(
                commandLock
            ) {

                try {

                    if (
                        !isSocketAlive()
                    ) {

                        Log.w(
                            TAG,
                            "Socket not alive before S. Reconnecting..."
                        )

                        if (
                            !reconnectTcp()
                        ) {

                            handler.post {

                                result.error(
                                    "ESP_CONNECTION",
                                    "ESP not connected.",
                                    null
                                )
                            }

                            return@synchronized
                        }
                    }

                    val inputStream =
                        input

                    val outputStream =
                        output

                    if (
                        inputStream == null ||
                        outputStream == null
                    ) {

                        handler.post {

                            result.error(
                                "ESP_STREAM",
                                "ESP stream unavailable.",
                                null
                            )
                        }

                        return@synchronized
                    }

                    clearInput(
                        inputStream
                    )

                    Log.d(
                        TAG,
                        "Sending S command"
                    )

                    outputStream.write(
                        'S'.code
                    )

                    outputStream.flush()

                    /*
                     * ESP:
                     *
                     * client.write(0);
                     * client.write(unlocked);
                     *
                     * TOTAL = 2 bytes
                     */
                    val response =
                        readExact(
                            inputStream,
                            STATUS_RESPONSE_SIZE,
                            5000
                        )

                    if (
                        response == null ||
                        response.size !=
                        STATUS_RESPONSE_SIZE
                    ) {

                        Log.e(
                            TAG,
                            "Invalid status response"
                        )

                        handler.post {

                            result.error(
                                "ESP_STATUS",
                                "Invalid status response. Expected 2 bytes.",
                                null
                            )
                        }

                        return@synchronized
                    }

                    val status =
                        response[0]
                            .toInt()
                            .and(0xFF)

                    val state =
                        response[1]
                            .toInt()
                            .and(0xFF)

                    Log.d(
                        TAG,
                        "S response: status=$status state=$state"
                    )

                    if (
                        status != 0
                    ) {

                        handler.post {

                            result.error(
                                "ESP_STATUS_DEVICE",
                                "ESP returned status=$status",
                                status
                            )
                        }

                        return@synchronized
                    }

                    handler.post {

                        result.success(
                            state
                        )
                    }

                } catch (
                    e: SocketTimeoutException
                ) {

                    Log.e(
                        TAG,
                        "Status response timeout",
                        e
                    )

                    closeSocket()

                    handler.post {

                        result.error(
                            "ESP_STATUS_TIMEOUT",
                            "ESP did not return status.",
                            null
                        )
                    }

                } catch (
                    e: Exception
                ) {

                    Log.e(
                        TAG,
                        "Status command error",
                        e
                    )

                    closeSocket()

                    handler.post {

                        result.error(
                            "ESP_STATUS_ERROR",
                            e.message
                                ?: "Unknown status error.",
                            null
                        )
                    }
                }
            }

        }.start()
    }

    private fun getPresenceStatus(
        result: MethodChannel.Result
    ) {

        Thread {

            synchronized(commandLock) {

                try {
                    if (!isSocketAlive() && !reconnectTcp()) {
                        handler.post { result.error("ESP_CONNECTION", "ESP not connected.", null) }
                        return@synchronized
                    }
                    val inputStream = input
                    val outputStream = output
                    if (inputStream == null || outputStream == null) {
                        handler.post { result.error("ESP_STREAM", "ESP stream unavailable.", null) }
                        return@synchronized
                    }
                    clearInput(inputStream)
                    outputStream.write('P'.code)
                    outputStream.flush()
                    val response = readExact(inputStream, PRESENCE_RESPONSE_SIZE, 5000)
                    if (response == null || response.size != PRESENCE_RESPONSE_SIZE) {
                        closeSocket()
                        handler.post { result.error("ESP_PRESENCE", "Invalid presence response. Expected 3 bytes.", null) }
                        return@synchronized
                    }
                    val status = response[0].toInt().and(0xFF)
                    if (status != 0) {
                        handler.post { result.error("ESP_PRESENCE_DEVICE", "ESP returned status=$status", status) }
                        return@synchronized
                    }
                    val lockState = response[1].toInt().and(0xFF)
                    val present = response[2].toInt().and(0xFF)
                    handler.post { result.success(listOf(lockState, present)) }
                } catch (e: Exception) {
                    Log.e(TAG, "Presence command error", e)
                    closeSocket()
                    handler.post { result.error("ESP_PRESENCE_ERROR", e.message ?: "Unknown presence error.", null) }
                }
            }
        }.start()
    }

    // ============================================================
    // RECONNECT TCP
    // ============================================================

    private fun reconnectTcp():
            Boolean {

        synchronized(
            socketLock
        ) {

            if (
                isSocketAlive()
            ) {

                return true
            }

            closeSocket()

            return try {

                val socket =
                    Socket()

                /*
                 * Android 10+:
                 *
                 * Always bind the TCP socket to the ESP
                 * WiFi network.
                 */
                if (
                    Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.Q
                ) {

                    val network =
                        boundNetwork

                    if (
                        network == null
                    ) {

                        Log.e(
                            TAG,
                            "No bound ESP network available"
                        )

                        return false
                    }

                    network.bindSocket(
                        socket
                    )
                }

                socket.connect(
                    InetSocketAddress(espIp, espPort),
                    10000
                )

                socket.soTimeout =
                    10000

                socket.keepAlive =
                    true

                socket.tcpNoDelay =
                    true

                currentSocket =
                    socket

                input =
                    socket.getInputStream()

                output =
                    socket.getOutputStream()

                Log.d(
                    TAG,
                    "TCP reconnect successful"
                )

                true

            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "TCP reconnect failed",
                    e
                )

                closeSocket()

                false
            }
        }
    }

    // ============================================================
    // READ EXACT
    // ============================================================

    private fun readExact(
        stream: InputStream,
        size: Int,
        timeoutMs: Long
    ): ByteArray? {

        if (
            size <= 0
        ) {

            return null
        }

        val buffer =
            ByteArray(
                size
            )

        var total =
            0

        val start =
            System.currentTimeMillis()

        while (
            total < size
        ) {

            /*
             * Our own timeout.
             */
            if (
                System.currentTimeMillis() -
                start >=
                timeoutMs
            ) {

                Log.e(
                    TAG,
                    "readExact timeout: $total/$size"
                )

                return null
            }

            try {

                /*
                 * InputStream.read() may return fewer bytes
                 * than requested.
                 *
                 * Therefore continue until the exact
                 * number of bytes is received.
                 */
                val count =
                    stream.read(
                        buffer,
                        total,
                        size - total
                    )

                if (
                    count < 0
                ) {

                    Log.e(
                        TAG,
                        "Socket closed while reading: $total/$size"
                    )

                    return null
                }

                if (
                    count > 0
                ) {

                    total += count

                    Log.d(
                        TAG,
                        "Received $total/$size bytes"
                    )
                }

            } catch (
                e: SocketTimeoutException
            ) {

                Log.e(
                    TAG,
                    "Socket read timeout: $total/$size"
                )

                return null

            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "readExact error",
                    e
                )

                return null
            }
        }

        return buffer
    }

    // ============================================================
    // CLEAR STALE INPUT
    // ============================================================

    private fun clearInput(
        stream: InputStream
    ) {

        try {

            var cleared =
                0

            while (
                stream.available() > 0
            ) {

                val value =
                    stream.read()

                if (
                    value < 0
                ) {
                    break
                }

                cleared++
            }

            if (
                cleared > 0
            ) {

                Log.w(
                    TAG,
                    "Cleared $cleared stale bytes"
                )
            }

        } catch (
            _: Exception
        ) {
        }
    }

    // ============================================================
    // SOCKET STATUS
    // ============================================================

    private fun isSocketAlive():
            Boolean {

        synchronized(
            socketLock
        ) {

            val socket =
                currentSocket
                    ?: return false

            return socket.isConnected &&
                    !socket.isClosed &&
                    !socket.isInputShutdown &&
                    !socket.isOutputShutdown
        }
    }

    // ============================================================
    // DISCONNECT
    // ============================================================

    private fun disconnect(
        result: MethodChannel.Result
    ) {

        try {

            unregisterNetworkCallback()

            closeSocket()

            boundNetwork =
                null

            result.success(
                true
            )

        } catch (
            e: Exception
        ) {

            result.error(
                "DISCONNECT_ERROR",
                e.message
                    ?: "Disconnect failed.",
                null
            )
        }
    }

    // ============================================================
    // NETWORK CALLBACK
    // ============================================================

    private fun unregisterNetworkCallback() {

        try {

            networkCallback?.let {

                connectivityManager
                    ?.unregisterNetworkCallback(
                        it
                    )
            }

        } catch (
            _: Exception
        ) {
        }

        networkCallback =
            null
    }

    // ============================================================
    // CLOSE SOCKET
    // ============================================================

    private fun closeSocket() {

        synchronized(
            socketLock
        ) {

            try {
                input?.close()
            } catch (
                _: Exception
            ) {
            }

            try {
                output?.close()
            } catch (
                _: Exception
            ) {
            }

            try {
                currentSocket?.close()
            } catch (
                _: Exception
            ) {
            }

            input =
                null

            output =
                null

            currentSocket =
                null
        }
    }

    // ============================================================
    // ACTIVITY DESTROY
    // ============================================================

    override fun onDestroy() {

        unregisterNetworkCallback()

        closeSocket()

        super.onDestroy()
    }
}
