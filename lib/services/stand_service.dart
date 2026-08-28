import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_exception.dart';
import '../core/logging/app_logger.dart';

/// Read-only stand queries used by the map and selectors. Ride-state changes
/// belong to CycleService/RideOperationService and are protected by RPCs.
class StandService {
  StandService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> getStands() async {
    try {
      final rows = await _client
          .from('stands')
          .select(
            'id, name, location, latitude, longitude, capacity, status, esp_mac, esp_ssid, esp_ip, esp_port, cycles(id, cycle_number, status, physical_state, last_verified_at)',
          )
          .eq('status', 'active')
          .order('name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _error('We could not load campus stands.', error);
    }
  }

  Future<Map<String, dynamic>> getStand(String id) async {
    try {
      final row = await _client
          .from('stands')
          .select('*')
          .eq('id', id)
          .maybeSingle();
      if (row == null)
        throw const AppException('This stand is not registered.');
      return Map<String, dynamic>.from(row);
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      if (error is AppException) rethrow;
      throw _error('We could not verify this stand.', error);
    }
  }

  /// Returns a privacy-preserving, server-authorized activity feed for a
  /// stand. The RPC limits the result to five events and exposes a display
  /// name rather than a student's email or user id.
  Future<List<Map<String, dynamic>>> getRecentActivity(
    String standId, {
    int limit = 5,
  }) async {
    try {
      final rows = await _client.rpc(
        'get_stand_activity',
        params: {'p_stand_id': standId, 'p_limit': limit},
      );
      return rows is List
          ? rows.map((row) => Map<String, dynamic>.from(row as Map)).toList()
          : const [];
    } catch (error, stackTrace) {
      AppLogger.error('SUPABASE', error, stackTrace);
      throw _error('We could not load stand activity.', error);
    }
  }

  AppException _error(String fallback, Object error) =>
      error is PostgrestException && error.message.isNotEmpty
      ? AppException(error.message, code: error.code)
      : AppException(fallback);
}
