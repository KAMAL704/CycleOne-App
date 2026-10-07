import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_exception.dart';
import '../core/logging/app_logger.dart';
import '../models/esp_endpoint.dart';

/// The only client-side access point for cycle, stand and ride data.
/// Writes that change a ride or a cycle use SECURITY DEFINER RPCs; a client
/// never updates a ride or a cycle row directly.
class CycleService {
  CycleService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> getCycle(String cycleId) async {
    try {
      final row = await _client.from('cycles').select('*').eq('id', cycleId).maybeSingle();
      if (row == null) throw const AppException('This cycle is not registered.');
      final cycle = Map<String, dynamic>.from(row);
      final standId = cycle['stand_id']?.toString();
      if (standId != null && standId.isNotEmpty) {
        cycle['stands'] = await _client.from('stands').select('*').eq('id', standId).maybeSingle();
      }
      return cycle;
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _databaseError(error, 'We could not verify that cycle.');
    }
  }

  Future<Map<String, dynamic>> getStand(String standId) async {
    try {
      final row = await _client.from('stands').select('*').eq('id', standId).maybeSingle();
      if (row == null) throw const AppException('This stand is not registered.');
      return Map<String, dynamic>.from(row);
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _databaseError(error, 'We could not verify that stand.');
    }
  }

  Future<List<Map<String, dynamic>>> getStands({bool onlyWithAvailableCycles = false}) async {
    try {
      final rows = await _client.from('stands').select('id, name, location, latitude, longitude, capacity, status, cycles(id, cycle_number, status, physical_state)').eq('status', 'active').order('name');
      final stands = List<Map<String, dynamic>>.from(rows).map((stand) {
        final cycles = stand['cycles'];
        if (cycles is List) {
          // Confirmed-absent rows are historical inventory records and should
          // not make an empty destination stand look occupied.
          stand['cycles'] = cycles
              .whereType<Map>()
              .where((cycle) => cycle['physical_state'] != 'absent')
              .toList();
        }
        return stand;
      }).toList();
      if (!onlyWithAvailableCycles) return stands;
      return stands.where((stand) {
        final cycles = stand['cycles'] as List? ?? const [];
        return cycles.any((cycle) => cycle is Map && cycle['status'] == 'available' && cycle['physical_state'] == 'present');
      }).toList();
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _databaseError(error, 'We could not load the stands.');
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableCyclesAtStand(String standId) async {
    try {
      final rows = await _client.from('cycles').select('id, cycle_number, qr_code, status, stand_id, physical_state, last_verified_at').eq('stand_id', standId).eq('status', 'available').eq('physical_state', 'present').order('cycle_number');
      return List<Map<String, dynamic>>.from(rows);
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _databaseError(error, 'We could not load cycles for this stand.');
    }
  }

  /// Resolves the MAC-only cycle QR format to the registered cycle row. A
  /// duplicate MAC is rejected instead of guessing which cycle to unlock.
  Future<String> resolveCycleIdFromMac(String mac) async {
    final normalized = EspEndpoint.normalizeMac(mac);
    if (normalized.isEmpty) {
      throw const AppException('This cycle QR contains an invalid ESP MAC.');
    }
    try {
      final rows = await _client
          .from('cycles')
          .select('id')
          .eq('esp_mac', normalized);
      var matches = List<Map<String, dynamic>>.from(rows);
      if (matches.isEmpty) {
        // Older inventory rows may not have copied esp_mac onto the cycle;
        // resolve the same MAC through its current stand as a compatibility
        // fallback.
        final stand = await _client
            .from('stands')
            .select('id')
            .eq('esp_mac', normalized)
            .maybeSingle();
        final standId = stand?['id']?.toString();
        if (standId != null) {
          final standCycles = await _client
              .from('cycles')
              .select('id')
              .eq('stand_id', standId)
              .inFilter('status', ['available', 'maintenance']);
          matches = List<Map<String, dynamic>>.from(standCycles);
        }
      }
      if (matches.isEmpty) {
        throw const AppException('No cycle is registered for this ESP MAC.');
      }
      if (matches.length > 1) {
        throw const AppException('This ESP MAC is assigned to multiple cycles. Ask the administrator to repair the cycle records.');
      }
      return matches.single['id'].toString();
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error('QR', error, stackTrace);
      throw _databaseError(error, 'We could not resolve this cycle QR.');
    }
  }

  Future<Map<String, dynamic>> syncCyclePresence({required String standId, required String espMac, required bool present}) async {
    try {
      final response = await _client.rpc('sync_cycle_presence', params: {
        'p_stand_id': standId,
        'p_esp_mac': espMac,
        'p_present': present,
      });
      if (response is! Map) throw const AppException('The server returned an invalid inventory response.');
      return Map<String, dynamic>.from(response);
    } catch (error, stackTrace) {
      AppLogger.error('INVENTORY', error, stackTrace);
      throw _databaseError(error, 'The stand inventory could not be verified.');
    }
  }

  Future<Map<String, dynamic>?> getActiveRide() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await _client.from('rides').select('*').eq('user_id', userId).eq('status', 'active').maybeSingle();
      if (row != null) return _attachRideRelations(Map<String, dynamic>.from(row));
      return getActiveTestRide();
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _databaseError(error, 'We could not check your active ride.');
    }
  }

  /// Test assignments deliberately live outside the real rides table.  They
  /// are still returned in the same shape as an active ride so the main Cycle
  /// screen can show one consistent active-cycle card.
  Future<Map<String, dynamic>?> getActiveTestRide() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await _client
          .from('admin_test_cycle_assignments')
          .select('id, user_id, cycle_id, stand_id, phase, note, created_at')
          .eq('user_id', userId)
          .eq('status', 'assigned')
          .maybeSingle();
      if (row == null) return null;
      final assignment = Map<String, dynamic>.from(row);
      final cycleId = assignment['cycle_id']?.toString();
      final standId = assignment['stand_id']?.toString();
      if (cycleId == null || cycleId.isEmpty) return null;
      final cycle = await _client
          .from('cycles')
          .select('id, cycle_number, status, stand_id, physical_state')
          .eq('id', cycleId)
          .maybeSingle();
      final stand = standId == null || standId.isEmpty
          ? null
          : await _client
                .from('stands')
                .select('id, name, location, latitude, longitude, capacity, status, esp_mac, esp_ssid, esp_password, esp_ip, esp_port')
                .eq('id', standId)
                .maybeSingle();
      return {
        ...assignment,
        'status': 'active',
        'test_mode': true,
        'test_phase': assignment['phase'] ?? 'assigned',
        'start_stand_id': standId,
        'started_at': assignment['created_at'],
        'cycles': cycle,
        'start_stand': stand,
      };
    } catch (error, stackTrace) {
      if (error is PostgrestException &&
          (error.code == 'PGRST205' ||
              error.message.toLowerCase().contains('admin_test_cycle_assignments'))) {
        // The test-mode migration is optional for older deployments.  A
        // normal user ride must continue to work until the migration is
        // applied, while the admin test panel will show its setup error.
        return null;
      }
      AppLogger.error('TEST_RIDE', error, stackTrace);
      throw _databaseError(error, 'We could not check your test cycle.');
    }
  }

  Future<List<Map<String, dynamic>>> getRideHistory() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    try {
      final rows = await _client
          .from('rides')
          .select('*')
          .eq('user_id', userId)
          .order('started_at', ascending: false)
          .limit(100);
      final rides = List<Map<String, dynamic>>.from(rows).map((row) => Map<String, dynamic>.from(row)).toList();
      if (rides.isEmpty) return rides;

      final cycleIds = rides.map((ride) => ride['cycle_id']?.toString()).whereType<String>().where((id) => id.isNotEmpty).toSet().toList();
      final standIds = rides
          .expand((ride) => [ride['start_stand_id']?.toString(), ride['end_stand_id']?.toString()])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final cycleRows = cycleIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await _client.from('cycles').select('id, cycle_number, stand_id').inFilter('id', cycleIds));
      final standRows = standIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await _client.from('stands').select('id, name, location').inFilter('id', standIds));
      final cycles = {for (final cycle in cycleRows) cycle['id'].toString(): cycle};
      final stands = {for (final stand in standRows) stand['id'].toString(): stand};
      for (final ride in rides) {
        ride['cycles'] = cycles[ride['cycle_id']?.toString()];
        ride['start_stand'] = stands[ride['start_stand_id']?.toString()];
        ride['end_stand'] = stands[ride['end_stand_id']?.toString()];
      }
      return rides;
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _databaseError(error, 'We could not load your ride history.');
    }
  }

  /// PostgREST relationship names can differ after a legacy-schema cutover.
  /// Fetching these three records explicitly keeps ride history working even
  /// while the API schema cache is rebuilding or constraint names differ.
  Future<Map<String, dynamic>> _attachRideRelations(Map<String, dynamic> ride) async {
    final cycleId = ride['cycle_id']?.toString();
    final standIds = [ride['start_stand_id']?.toString(), ride['end_stand_id']?.toString()]
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (cycleId != null && cycleId.isNotEmpty) {
      ride['cycles'] = await _client.from('cycles').select('id, cycle_number, stand_id').eq('id', cycleId).maybeSingle();
    }
    if (standIds.isNotEmpty) {
      final rows = List<Map<String, dynamic>>.from(await _client.from('stands').select('id, name, location').inFilter('id', standIds));
      final stands = {for (final stand in rows) stand['id'].toString(): stand};
      ride['start_stand'] = stands[ride['start_stand_id']?.toString()];
      ride['end_stand'] = stands[ride['end_stand_id']?.toString()];
    }
    return ride;
  }

  /// Called only after the physical lock reported and verified an unlock.
  Future<Map<String, dynamic>> startRide({required String cycleId, required String standId, required String espMac}) async {
    try {
      final response = await _client.rpc('start_cycle_ride', params: {'p_cycle_id': cycleId, 'p_start_stand_id': standId, 'p_esp_mac': espMac});
      if (response is! Map) throw const AppException('The server returned an invalid start-ride response.');
      return Map<String, dynamic>.from(response);
    } catch (error, stackTrace) {
      AppLogger.error('RIDE', error, stackTrace);
      throw _databaseError(error, 'The lock opened, but the ride could not be recorded.');
    }
  }

  /// Called only after the physical lock reported and verified a lock.
  Future<void> endRide({required String rideId, required String cycleId, required String destinationStandId, required String espMac}) async {
    try {
      final response = await _client.rpc('end_cycle_ride', params: {
        'p_ride_id': rideId,
        'p_cycle_id': cycleId,
        'p_end_stand_id': destinationStandId,
        'p_esp_mac': espMac,
      });
      if (response != true) throw const AppException('The server did not complete the return.');
    } catch (error, stackTrace) {
      AppLogger.error('RIDE', error, stackTrace);
      throw _databaseError(error, 'The lock closed, but the return could not be recorded.');
    }
  }

  /// Test rides use a separate assignment state machine.  No real cycle or
  /// ride row is changed, which lets an admin test an unavailable/stale cycle
  /// against a real ESP safely.
  Future<Map<String, dynamic>> startTestRide({required String cycleId, required String standId, required String espMac}) async {
    try {
      final response = await _client.rpc('admin_test_start_cycle', params: {
        'p_cycle_id': cycleId,
        'p_stand_id': standId,
        'p_esp_mac': espMac,
      });
      if (response is! Map) throw const AppException('The server returned an invalid test-ride response.');
      return Map<String, dynamic>.from(response);
    } catch (error, stackTrace) {
      AppLogger.error('TEST_RIDE', error, stackTrace);
      throw _databaseError(error, 'The test cycle could not be started.');
    }
  }

  Future<void> endTestRide({required String cycleId, required String destinationStandId, required String espMac}) async {
    try {
      final response = await _client.rpc('admin_test_end_cycle', params: {
        'p_cycle_id': cycleId,
        'p_end_stand_id': destinationStandId,
        'p_esp_mac': espMac,
      });
      if (response != true) throw const AppException('The server did not complete the test return.');
    } catch (error, stackTrace) {
      AppLogger.error('TEST_RIDE', error, stackTrace);
      throw _databaseError(error, 'The test cycle could not be returned.');
    }
  }

  AppException _databaseError(Object error, String fallback) {
    if (error is AppException) return error;
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (message.contains('already has an active ride')) return const AppException('You already have an active ride.');
      if (message.contains('no longer available') || message.contains('cycle is not available')) return const AppException('That cycle is no longer available.');
      if (message.contains('destination stand is full')) return const AppException('That stand is full. Choose another powered stand.');
      if (message.contains('destination stand is unavailable')) return const AppException('That stand is not accepting returns right now.');
      if (message.contains('multiple physically present cycles') || message.contains('multiple cycles assigned')) {
        return const AppException('This stand has duplicate cycle records. Refresh inventory or ask the administrator to repair it.');
      }
      if (message.contains('esp mac already belongs')) return const AppException('This ESP MAC is already assigned to another stand.');
      if (message.contains('active ride could not be verified')) return const AppException('Your active ride could not be verified. Refresh and try again.');
      return AppException(error.message.isEmpty ? fallback : error.message, code: error.code);
    }
    return AppException(fallback);
  }
}
