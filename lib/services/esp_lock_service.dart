import 'dart:math';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class ESPLockService {
  // ============================================================
  // ESP CONFIGURATION
  // ============================================================

  static const String espSsid = 'CycleOneS1';
  static const String espPassword = 'CycleOne';
  static const String espIp = '10.10.10.10';
  static const int espPort = 80;

  static const String keyHex = '1E171366E3EDDCE2923BC768623606F1';

  // ============================================================
  // PROTOCOL CONFIGURATION
  // ============================================================

  static const int uResponseSize = 41;
  static const int tokenSize = 40;
  static const int timeoutSeconds = 20;

  // ============================================================
  // METHOD CHANNEL
  // ============================================================

  static const MethodChannel _channel = MethodChannel('cycleone/esp_wifi');

  // ============================================================
  // DUPLICATE COMMAND PROTECTION
  // ============================================================

  static bool _commandInProgress = false;
  static String? _activeCommandAction;

  // ============================================================
  // PERMISSION HANDLING
  // ============================================================

  static Future<bool> requestPermissions() async {
    try {
      print('[CycleOne ESP] 🔐 Checking permissions...');

      final locationStatus = await Permission.location.status;

      if (locationStatus.isDenied) {
        print('[CycleOne ESP] 📱 Requesting location permission...');
        final status = await Permission.location.request();
        if (status.isDenied) {
          print('[CycleOne ESP] ❌ Location permission denied');
          return false;
        }
      }

      if (locationStatus.isPermanentlyDenied) {
        print('[CycleOne ESP] ❌ Location permission permanently denied');
        print('[CycleOne ESP] 💡 Please enable location in app settings');
        return false;
      }

      print('[CycleOne ESP] ✅ All permissions granted');
      return true;
    } catch (e) {
      print('[CycleOne ESP] ❌ Permission error: $e');
      return false;
    }
  }

  // ============================================================
  // CONNECTION
  // ============================================================

  static Future<bool> connectToESPWithNative({
    required String mac,
  }) async {
    try {
      final normalizedMac = normalizeMac(mac);

      print('[CycleOne ESP] =================================');
      print('[CycleOne ESP] 🔗 Connecting to ESP');
      print('[CycleOne ESP] 📡 SSID: $espSsid');
      print('[CycleOne ESP] 📡 MAC: $normalizedMac');
      print('[CycleOne ESP] 🌐 IP: $espIp:$espPort');

      final result = await _channel
          .invokeMethod('connectToEsp', {
        'mac': normalizedMac,
      })
          .timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () {
          print('[CycleOne ESP] ⏰ Connection timeout');
          return false;
        },
      );

      print('[CycleOne ESP] Connection result: $result');
      return result == true;
    } on PlatformException catch (e) {
      print('[CycleOne ESP] ❌ Connection error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('[CycleOne ESP] ❌ Connection exception: $e');
      return false;
    }
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  static Future<void> disconnectESP() async {
    try {
      await _channel.invokeMethod('disconnectFromEsp');
      print('[CycleOne ESP] 🔌 Disconnected');
    } catch (e) {
      print('[CycleOne ESP] Disconnect error: $e');
    }
  }

  // ============================================================
  // CONNECTION STATUS
  // ============================================================

  static Future<bool> isConnectedToESP() async {
    try {
      final result = await _channel.invokeMethod('getConnectionStatus');

      if (result == true) {
        print('[CycleOne ESP] ✅ Native says connected');
        return true;
      }

      try {
        final status = await getStatusNative();
        if (status != null) {
          print('[CycleOne ESP] ✅ ESP responding to status');
          return true;
        }
      } catch (_) {
        print('[CycleOne ESP] ⚠️ Status check failed');
      }

      print('[CycleOne ESP] ❌ ESP not connected');
      return false;
    } catch (e) {
      print('[CycleOne ESP] Connection status error: $e');
      return false;
    }
  }

  // ============================================================
  // SEND U
  // ============================================================

  static Future<Uint8List?> sendUNative() async {
    try {
      print('[CycleOne ESP] =================================');
      print('[CycleOne ESP] 📤 Sending U command via native...');

      final result = await _channel
          .invokeMethod('sendU')
          .timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () {
          print('[CycleOne ESP] ⏰ U command timeout');
          return null;
        },
      );

      if (result == null) {
        print('[CycleOne ESP] ❌ U returned null');
        return null;
      }

      final response = Uint8List.fromList(List<int>.from(result));
      print('[CycleOne ESP] 📥 U response received: ${response.length} bytes');

      if (response.isEmpty) {
        print('[CycleOne ESP] ❌ Empty response');
        return null;
      }

      Uint8List token;

      if (response.length == uResponseSize) {
        final status = response[0];
        print('[CycleOne ESP] 📥 ESP status byte: $status');

        if (status != 0) {
          print('[CycleOne ESP] ❌ ESP returned error status: $status');
          return null;
        }

        token = Uint8List.fromList(response.sublist(1, uResponseSize));
        print('[CycleOne ESP] 🔐 Extracted token from 41-byte response');

      } else if (response.length == tokenSize) {
        token = response;
        print('[CycleOne ESP] 🔐 Using token directly (40 bytes, no status)');

      } else {
        print('[CycleOne ESP] ❌ Invalid response length: ${response.length}');
        print('[CycleOne ESP] Expected: $uResponseSize or $tokenSize bytes');
        return null;
      }

      print('[CycleOne ESP] 🔐 Token length: ${token.length} bytes');

      if (token.length != tokenSize) {
        print('[CycleOne ESP] ❌ Invalid token length: ${token.length}');
        print('[CycleOne ESP] Expected exactly $tokenSize bytes');
        return null;
      }

      final hexString = token.take(10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('[CycleOne ESP] 🔐 Token first 10 bytes: $hexString');

      print('[CycleOne ESP] ✅ 40-byte token ready');
      return token;

    } on PlatformException catch (e) {
      print('[CycleOne ESP] ❌ U error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('[CycleOne ESP] ❌ U exception: $e');
      return null;
    }
  }

  // ============================================================
  // SEND T
  // ============================================================

  static Future<bool> sendTNative(Uint8List token) async {
    try {
      if (token.length != tokenSize) {
        print('[CycleOne ESP] ❌ Refusing T command');
        print('[CycleOne ESP] Invalid token length: ${token.length}');
        print('[CycleOne ESP] Expected: $tokenSize');
        return false;
      }

      print('[CycleOne ESP] =================================');
      print('[CycleOne ESP] 📤 Sending T command...');
      print('[CycleOne ESP] 🔐 Token length: ${token.length}');

      final result = await _channel
          .invokeMethod('sendT', {
        'token': token.toList(),
      })
          .timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () {
          print('[CycleOne ESP] ⏰ T command timeout');
          return false;
        },
      );

      print('[CycleOne ESP] T result: $result');
      return result == true;
    } on PlatformException catch (e) {
      print('[CycleOne ESP] ❌ T error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('[CycleOne ESP] ❌ T exception: $e');
      return false;
    }
  }

  // ============================================================
  // GET STATUS
  // ============================================================

  static Future<int?> getStatusNative() async {
    try {
      final result = await _channel
          .invokeMethod('getStatus')
          .timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('[CycleOne ESP] ⏰ Status timeout');
          return null;
        },
      );

      if (result == null) return null;

      final status = result as int;
      print('[CycleOne ESP] Status: ${status == 1 ? "UNLOCKED" : "LOCKED"}');
      return status;
    } catch (e) {
      print('[CycleOne ESP] ❌ Status error: $e');
      return null;
    }
  }

  // ============================================================
  // UNLOCK
  // ============================================================

  static Future<bool> unlockNative(String mac) async {
    print('[CycleOne ESP] 🟢 unlockNative() CALLED');

    if (!await requestPermissions()) {
      print('[CycleOne ESP] ❌ Permission denied');
      return false;
    }

    return _executeCommandProtected(mac, 'unlock');
  }

  // ============================================================
  // LOCK
  // ============================================================

  static Future<bool> lockNative(String mac) async {
    print('[CycleOne ESP] 🔴 lockNative() CALLED');

    if (!await requestPermissions()) {
      print('[CycleOne ESP] ❌ Permission denied');
      return false;
    }

    return _executeCommandProtected(mac, 'lock');
  }

  // ============================================================
  // PROTECTED COMMAND EXECUTION
  // ============================================================

  static Future<bool> _executeCommandProtected(String mac, String action) async {
    if (action != 'unlock' && action != 'lock') {
      print('[CycleOne ESP] ❌ Invalid command action: $action');
      return false;
    }

    if (_commandInProgress) {
      print('[CycleOne ESP] ⚠️ COMMAND ALREADY IN PROGRESS');
      print('[CycleOne ESP] ⚠️ Active command: $_activeCommandAction');
      print('[CycleOne ESP] ⚠️ New command: $action');
      print('[CycleOne ESP] ❌ Duplicate command BLOCKED');
      return false;
    }

    _commandInProgress = true;
    _activeCommandAction = action;

    print('[CycleOne ESP] 🔒 Command lock acquired: $action');

    try {
      final result = await _executeCommandNative(mac, action);
      return result;
    } catch (e) {
      print('[CycleOne ESP] ❌ Protected command error: $e');
      return false;
    } finally {
      _commandInProgress = false;
      _activeCommandAction = null;
      print('[CycleOne ESP] 🔓 Command lock released');
    }
  }

  // ============================================================
  // MAIN COMMAND EXECUTION
  // ============================================================

  static Future<bool> _executeCommandNative(String mac, String action) async {
    try {
      print('[CycleOne ESP] =================================');
      print('[CycleOne ESP] 🚀 _executeCommandNative START');
      print('[CycleOne ESP] 🚀 Action: $action');
      print('[CycleOne ESP] 🚀 MAC: $mac');
      print('[CycleOne ESP] === $action START ===');

      final connected = await connectToESPWithNative(mac: mac);
      if (!connected) {
        print('[CycleOne ESP] ❌ Failed to connect');
        return false;
      }
      print('[CycleOne ESP] ✅ ESP connected');

      final token = await sendUNative();
      if (token == null) {
        print('[CycleOne ESP] ❌ Failed to get U token');
        return false;
      }
      print('[CycleOne ESP] ✅ U token received: ${token.length} bytes');

      if (token.length != tokenSize) {
        print('[CycleOne ESP] ❌ U token invalid');
        return false;
      }

      // ✅ Pass MAC to Edge Function for verification
      final transformedToken = await _transformToken(token, action, mac);
      if (transformedToken == null) {
        print('[CycleOne ESP] ❌ Failed to transform token');
        return false;
      }
      print('[CycleOne ESP] ✅ Transformed token: ${transformedToken.length} bytes');

      if (transformedToken.length != tokenSize) {
        print('[CycleOne ESP] ❌ Transformed token invalid');
        return false;
      }

      final success = await sendTNative(transformedToken);
      if (!success) {
        print('[CycleOne ESP] ❌ T command failed');
        return false;
      }

      print('[CycleOne ESP] =================================');
      print('[CycleOne ESP] === $action SUCCESS ===');
      print('[CycleOne ESP] =================================');
      return true;
    } catch (e) {
      print('[CycleOne ESP] ❌ $action error: $e');
      return false;
    }
  }

  // ============================================================
  // SUPABASE EDGE FUNCTION - WITH MAC VERIFICATION ✅
  // ============================================================

  static Future<Uint8List?> _transformToken(
      Uint8List token,
      String action,
      String mac, // ✅ NEW: MAC from QR/Cycle
      ) async {
    try {
      print('[CycleOne ESP] =================================');
      print('[CycleOne ESP] 🔐 Transforming token for: $action');
      print('[CycleOne ESP] 📡 MAC: $mac');
      print('[CycleOne ESP] 📥 Received token length: ${token.length}');

      if (token.length != tokenSize) {
        print('[CycleOne ESP] ❌ Invalid token length: ${token.length}');
        print('[CycleOne ESP] Expected exactly $tokenSize bytes');
        return null;
      }

      if (action != 'unlock' && action != 'lock') {
        print('[CycleOne ESP] ❌ Invalid action: $action');
        return null;
      }

      if (mac.isEmpty) {
        print('[CycleOne ESP] ❌ Empty MAC provided for verification');
        return null;
      }

      print('[CycleOne ESP] 📤 Sending to Edge Function with MAC verification');

      final response = await Supabase.instance.client.functions
          .invoke(
        'transform-token',
        body: {
          'token': token.toList(),
          'action': action,
          'mac': mac, // ✅ Send MAC to Edge Function
        },
      )
          .timeout(
        Duration(seconds: 15),
        onTimeout: () {
          print('[CycleOne ESP] ⏰ Edge Function timeout');
          throw TimeoutException('Edge Function timeout');
        },
      );

      print('[CycleOne ESP] 📥 Edge Function status: ${response.status}');
      print('[CycleOne ESP] 📥 Edge Function response: ${response.data}');

      // ✅ Handle MAC mismatch (401)
      if (response.status == 401) {
        final data = response.data;
        print('[CycleOne ESP] ❌ MAC MISMATCH!');
        print('[CycleOne ESP] ❌ ${data?['error'] ?? 'Wrong ESP'}');

        if (data?['espMac'] != null) {
          print('[CycleOne ESP] 📡 ESP MAC: ${data['espMac']}');
        }

        return null;
      }

      if (response.status == 200) {
        final data = response.data;
        if (data == null) {
          print('[CycleOne ESP] ❌ Empty Edge Function response');
          return null;
        }

        // ✅ Check if MAC was verified
        if (data['macVerified'] == false) {
          print('[CycleOne ESP] ❌ MAC verification failed!');
          print('[CycleOne ESP] ❌ Wrong ESP detected!');

          if (data['espMac'] != null) {
            print('[CycleOne ESP] 📡 ESP MAC: ${data['espMac']}');
          }

          return null;
        }

        print('[CycleOne ESP] ✅ MAC verified: ${data['espMac'] ?? 'unknown'}');

        final transformed = data['transformedToken'];
        if (transformed == null) {
          print('[CycleOne ESP] ❌ transformedToken missing');
          return null;
        }

        final transformedList = List<int>.from(transformed);
        print('[CycleOne ESP] 🔐 Transformed token length: ${transformedList.length}');

        if (transformedList.length != tokenSize) {
          print('[CycleOne ESP] ❌ Edge Function returned ${transformedList.length} bytes');
          print('[CycleOne ESP] Expected exactly $tokenSize bytes');
          return null;
        }

        final transformedToken = Uint8List.fromList(transformedList);
        print('[CycleOne ESP] ✅ Token transformed successfully');
        print('[CycleOne ESP] 📤 Ready for T command: ${transformedToken.length} bytes');
        return transformedToken;
      }

      print('[CycleOne ESP] ❌ Transform failed');
      print('[CycleOne ESP] Status: ${response.status}');
      print('[CycleOne ESP] Error: ${response.data}');
      return null;
    } catch (e) {
      print('[CycleOne ESP] ❌ Transform error: $e');
      return null;
    }
  }

  // ============================================================
  // TEST NATIVE CONNECTION
  // ============================================================

  static Future<bool> testNativeConnection({required String mac}) async {
    try {
      print('[CycleOne ESP] 🧪 Testing native connection...');

      if (!await requestPermissions()) {
        print('[CycleOne ESP] ❌ Permission denied');
        return false;
      }

      final normalizedMac = normalizeMac(mac);
      final result = await _channel.invokeMethod('connectToEsp', {
        'mac': normalizedMac,
      });

      print('[CycleOne ESP] Native test result: $result');

      if (result == true) {
        final status = await getStatusNative();
        print('[CycleOne ESP] Native status: ${status == 1 ? "UNLOCKED" : "LOCKED"}');
        return true;
      }

      return false;
    } catch (e) {
      print('[CycleOne ESP] Native test error: $e');
      return false;
    }
  }

  // ============================================================
  // MAC NORMALIZATION
  // ============================================================

  static String normalizeMac(String mac) {
    final cleaned = mac
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toUpperCase();

    if (cleaned.length == 12 && RegExp(r'^[0-9A-F]{12}$').hasMatch(cleaned)) {
      return cleaned.replaceAllMapped(
        RegExp(r'.{2}'),
            (match) => '${match.group(0)}:',
      ).replaceFirst(RegExp(r':$'), '');
    }

    return mac;
  }

  // ============================================================
  // LEGACY METHODS
  // ============================================================

  static Future<bool> connectToESP() async {
    print('[CycleOne ESP] ⚠️ Legacy connectToESP() called');
    try {
      final result = await _channel.invokeMethod('connectToEsp', {
        'mac': '',
      });
      print('[CycleOne ESP] Legacy connection result: $result');
      return result == true;
    } catch (e) {
      print('[CycleOne ESP] Legacy connection error: $e');
      return false;
    }
  }

  static Future<bool> unlock() async {
    print('[CycleOne ESP] 🔓 Legacy unlock() called');
    return _executeCommandProtected('', 'unlock');
  }

  static Future<bool> lock() async {
    print('[CycleOne ESP] 🔒 Legacy lock() called');
    return _executeCommandProtected('', 'lock');
  }

  static Future<int?> getStatus() async {
    return await getStatusNative();
  }

  // ============================================================
  // LEGACY ENCRYPTION
  // ============================================================

  static Uint8List _encryptCommand(Uint8List data, int verificationInt, int action) {
    final keyBytes = _hexStringToBytes(keyHex);
    final keyParam = KeyParameter(Uint8List.fromList(keyBytes));
    final iv = Uint8List(16);
    final random = Random.secure();
    for (int i = 0; i < 16; i++) {
      iv[i] = random.nextInt(256);
    }

    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(keyParam, iv));

    final paddedData = Uint8List(16);
    paddedData.setAll(0, data);
    final output = Uint8List(16);
    cipher.processBlock(paddedData, 0, output, 0);

    final result = Uint8List(40);
    final verificationBytes = ByteData(8)..setUint64(0, verificationInt);
    result.setAll(0, verificationBytes.buffer.asUint8List());
    result.setAll(8, iv);
    result.setAll(24, output);

    print('[CycleOne ESP] 📤 Legacy command encrypted: ${result.length} bytes');
    print('[CycleOne ESP] Action: ${action == 1 ? "UNLOCK" : "LOCK"}');
    return result;
  }

  // ============================================================
  // HEX TO BYTES
  // ============================================================

  static List<int> _hexStringToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      final high = int.parse(hex.substring(i, i + 1), radix: 16);
      final low = int.parse(hex.substring(i + 1, i + 2), radix: 16);
      result.add((high << 4) + low);
    }
    return result;
  }

  // ============================================================
  // BYTES TO HEX
  // ============================================================

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
}