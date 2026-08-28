import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_exception.dart';
import '../core/logging/app_logger.dart';
import '../models/esp_endpoint.dart';

enum LockAction { unlock, lock }

class HardwareTransition {
  const HardwareTransition.changed() : changed = true, alreadyInRequestedState = false;
  const HardwareTransition.alreadyRequested() : changed = false, alreadyInRequestedState = true;

  final bool changed;
  final bool alreadyInRequestedState;
}

class EspPhysicalState {
  const EspPhysicalState({required this.locked, required this.cyclePresent});

  final bool locked;
  final bool cyclePresent;
}

/// Native ESP transport. T commands are deliberately never retried: a lost
/// response is ambiguous because the relay may already have moved.
class ESPLockService {
  ESPLockService({MethodChannel? channel}) : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel('cycleone/esp_wifi');
  static const int _tokenLength = 40;
  static const int _locked = 0;
  static const int _unlocked = 1;

  final MethodChannel _channel;
  bool _commandInProgress = false;
  EspEndpoint? _connectedEndpoint;

  Future<void> ensurePermissions() async {
    final location = await Permission.locationWhenInUse.request();
    if (!location.isGranted) throw const AppException('Location permission is required to connect to a nearby stand.');
    try {
      final nearby = await Permission.nearbyWifiDevices.request();
      if (!nearby.isGranted && !nearby.isLimited) {
        throw const AppException('Nearby Wi-Fi permission is required to connect to a stand.');
      }
    } on UnsupportedError {
      // Not exposed on the current platform/API level.
    }
  }

  Future<void> connect(EspEndpoint endpoint) async {
    if (_connectedEndpoint?.mac == endpoint.mac && await isConnected()) return;
    await disconnect();
    try {
      AppLogger.info('ESP', 'Connecting to expected BSSID ${endpoint.mac}');
      final connected = await _channel.invokeMethod<bool>('connectToEsp', {
        'mac': endpoint.mac,
        'ssid': endpoint.ssid,
        'password': endpoint.password,
        'ip': endpoint.host,
        'port': endpoint.port,
      }).timeout(const Duration(seconds: 30));
      if (connected != true) throw const AppException('The requested stand could not be reached.');
      _connectedEndpoint = endpoint;
      AppLogger.info('ESP', 'Connected to exact requested BSSID');
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error('WIFI', error, stackTrace);
      throw AppException(_connectionMessage(error.code));
    } on TimeoutException {
      throw const AppException('Connection to the stand timed out. Make sure it is powered and nearby.');
    }
  }

  Future<bool> isConnected() async {
    try {
      return await _channel.invokeMethod<bool>('getConnectionStatus') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Reads the stand's physical inventory status without pulsing the relay.
  /// The firmware returns lock state plus a presence-sensor result. Firmware
  /// without a sensor uses locked-as-present as a conservative fallback.
  Future<EspPhysicalState> readPresence(EspEndpoint endpoint) async {
    await ensurePermissions();
    try {
      await connect(endpoint);
      final raw = await _channel.invokeMethod<dynamic>('getPresenceStatus').timeout(const Duration(seconds: 12));
      final values = List<int>.from(raw as List);
      if (values.length != 2 || !values.every((value) => value == 0 || value == 1)) {
        throw const AppException('The stand returned an invalid physical inventory state.');
      }
      return EspPhysicalState(locked: values[0] == _locked, cyclePresent: values[1] == 1);
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error('ESP_PRESENCE', error, stackTrace);
      throw AppException(_connectionMessage(error.code));
    } on TimeoutException {
      throw const AppException('The stand did not return its inventory state in time.');
    } finally {
      await disconnect();
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<bool>('disconnectFromEsp');
    } catch (_) {
      // Native cleanup is best effort; no lock action is being performed here.
    } finally {
      _connectedEndpoint = null;
    }
  }

  Future<HardwareTransition> transition({
    required EspEndpoint endpoint,
    required LockAction action,
    required String cycleId,
    required String standId,
  }) async {
    if (_commandInProgress) throw const AppException('Another lock operation is already in progress.');
    _commandInProgress = true;
    try {
      await ensurePermissions();
      await connect(endpoint);
      final expectedState = action == LockAction.unlock ? _unlocked : _locked;
      final before = await _status();
      if (before == expectedState) return const HardwareTransition.alreadyRequested();

      final token = await _sendU();
      final transformed = await _transformToken(
        token: token,
        action: action,
        endpoint: endpoint,
        cycleId: cycleId,
        standId: standId,
      );
      try {
        await _sendT(transformed);
      } on AppException catch (error) {
        if (error.code != 'HARDWARE_AMBIGUOUS') rethrow;
        // The relay may have changed before the TCP response was lost. A
        // fresh status read is safe; retrying T would not be.
        try {
          await disconnect();
          await connect(endpoint);
          final observed = await _status();
          if (observed != expectedState) throw error;
          AppLogger.info('ESP', 'Recovered physical state after ambiguous T response');
        } catch (_) {
          throw error;
        }
      }

      final after = await _status();
      if (after != expectedState) throw const AppException('The stand did not confirm the requested physical lock state.');
      AppLogger.info('ESP', '${action.name} state confirmed');
      return const HardwareTransition.changed();
    } finally {
      _commandInProgress = false;
      await disconnect();
    }
  }

  Future<int> _status() async {
    try {
      final value = await _channel.invokeMethod<int>('getStatus').timeout(const Duration(seconds: 12));
      if (value != _locked && value != _unlocked) throw const AppException('The stand returned an invalid lock state.');
      return value!;
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error('TCP', error, stackTrace);
      throw AppException(_connectionMessage(error.code));
    } on TimeoutException {
      throw const AppException('The stand did not respond in time. Please try another powered stand.');
    }
  }

  Future<Uint8List> _sendU() async {
    try {
      AppLogger.info('TCP', 'Sending U');
      final raw = await _channel.invokeMethod<dynamic>('sendU').timeout(const Duration(seconds: 12));
      final response = Uint8List.fromList(List<int>.from(raw as List));
      if (response.length != 41 || response.first != 0) throw const AppException('The stand rejected its secure token request.');
      return Uint8List.fromList(response.sublist(1));
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error('TCP', error, stackTrace);
      throw AppException(_connectionMessage(error.code));
    } on TimeoutException {
      throw const AppException('The stand did not return its secure token in time.');
    }
  }

  Future<void> _sendT(Uint8List token) async {
    if (token.length != _tokenLength) throw const AppException('The secure lock token is invalid.');
    try {
      AppLogger.info('TCP', 'Sending T');
      final success = await _channel.invokeMethod<bool>('sendT', {'token': token.toList()}).timeout(const Duration(seconds: 12));
      if (success != true) throw const AppException('The stand rejected the physical lock command.');
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error('TCP', error, stackTrace);
      if (error.code.startsWith('ESP_T_')) {
        throw const AppException('The lock response was lost. The physical state is being checked; do not retry another cycle.', code: 'HARDWARE_AMBIGUOUS');
      }
      throw AppException(_connectionMessage(error.code));
    } on TimeoutException {
      throw const AppException('The lock command response was lost. The physical state is being checked; do not retry immediately.', code: 'HARDWARE_AMBIGUOUS');
    }
  }

  Future<Uint8List> _transformToken({
    required Uint8List token,
    required LockAction action,
    required EspEndpoint endpoint,
    required String cycleId,
    required String standId,
  }) async {
    try {
      AppLogger.info('AES', 'Requesting server-side token transformation');
      final response = await Supabase.instance.client.functions.invoke('transform-token', body: {
        'token': token.toList(),
        'action': action.name,
        'mac': endpoint.mac,
        'cycleId': cycleId,
        'standId': standId,
      });
      final data = response.data;
      if (response.status != 200 || data is! Map || data['success'] != true || data['macVerified'] != true) {
        throw const AppException('The server could not authorize this lock operation.');
      }
      final transformed = data['transformedToken'];
      if (transformed is! List || transformed.length != _tokenLength) {
        throw const AppException('The server returned an invalid secure lock token.');
      }
      return Uint8List.fromList(transformed.cast<num>().map((byte) => byte.toInt()).toList());
    } on FunctionException catch (error, stackTrace) {
      AppLogger.error('AES', error, stackTrace);
      throw const AppException('The server could not authorize this lock operation.');
    }
  }

  String _connectionMessage(String code) => switch (code) {
        'PERMISSION_DENIED' => 'Nearby Wi-Fi permission is required to connect to the stand.',
        'WIFI_UNAVAILABLE' || 'WIFI_TIMEOUT' => 'The requested stand is unavailable. Make sure it is powered and nearby.',
        'BSSID_MISMATCH' => 'The phone reached a different stand, so the operation was stopped safely.',
        'ESP_CONNECTION' || 'SOCKET_ERROR' => 'Connection to the cycle lock was lost. Please make sure the stand is powered on and try again.',
        _ => 'Unable to communicate with this stand. Please try again while nearby.',
      };
}
