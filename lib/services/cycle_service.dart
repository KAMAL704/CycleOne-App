import 'package:supabase_flutter/supabase_flutter.dart';
import 'esp_lock_service.dart';

class CycleService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // GET CYCLES FOR STAND
  // ============================================================

  static Future<List<Map<String, dynamic>>> getCyclesForStand(String standId) async {
    try {
      final response = await _supabase
          .from('cycles')
          .select('*')
          .eq('stand_id', standId)
          .eq('status', 'available');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('[CycleService] Error fetching cycles for stand: $e');
      return [];
    }
  }

  // ============================================================
  // GET STANDS WITH AVAILABLE CYCLES
  // ============================================================

  static Future<List<Map<String, dynamic>>> getStandsWithAvailableCycles() async {
    try {
      final response = await _supabase
          .from('stands')
          .select('*, blocks(name), cycles!stand_id(id, status, mac_address)')
          .order('name');

      final standsWithCycles = response.where((stand) {
        final cycles = stand['cycles'] as List?;
        if (cycles == null) return false;
        return cycles.any((c) => c['status'] == 'available');
      }).toList();

      return List<Map<String, dynamic>>.from(standsWithCycles);
    } catch (e) {
      print('[CycleService] Error fetching stands with cycles: $e');
      return [];
    }
  }

  // ============================================================
  // GET ALL STANDS
  // ============================================================

  static Future<List<Map<String, dynamic>>> getAllStands() async {
    try {
      final response = await _supabase
          .from('stands')
          .select('*, blocks(name), cycles!stand_id(id, status, mac_address)')
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('[CycleService] Error fetching all stands: $e');
      return [];
    }
  }

  // ============================================================
  // CHECK CYCLE IN STAND
  // ============================================================

  static Future<bool> checkCycleInStand(String standId, String cycleId) async {
    try {
      print('[CycleService] 🔍 Checking cycle in stand');
      print('[CycleService] 📍 Stand: $standId');
      print('[CycleService] 🚲 Cycle: $cycleId');

      if (standId.isEmpty || cycleId.isEmpty) {
        print('[CycleService] ❌ Empty stand or cycle ID');
        return false;
      }

      final cycleData = await _supabase
          .from('cycles')
          .select('id, status, stand_id, mac_address')
          .eq('id', cycleId)
          .maybeSingle();

      if (cycleData == null) {
        print('[CycleService] ❌ Cycle not found in database');
        return false;
      }

      print('[CycleService] 📊 Cycle data: $cycleData');

      if (cycleData['stand_id'] != standId) {
        print('[CycleService] ❌ Cycle is not in this stand');
        print('[CycleService] 📍 Expected stand: $standId');
        print('[CycleService] 📍 Actual stand: ${cycleData['stand_id']}');
        return false;
      }

      if (cycleData['status'] != 'available') {
        print('[CycleService] ❌ Cycle is not available');
        print('[CycleService] 📊 Status: ${cycleData['status']}');
        return false;
      }

      print('[CycleService] ✅ Cycle is in stand and available');
      return true;
    } catch (e) {
      print('[CycleService] ❌ Error checking cycle: $e');
      return false;
    }
  }

  // ============================================================
  // GET CYCLE BY MAC (Multiple format support)
  // ============================================================

  static Future<Map<String, dynamic>?> getCycleByMac(String mac) async {
    try {
      print('[CycleService] 🔍 Looking for cycle with MAC: "$mac"');

      if (mac.isEmpty) {
        print('[CycleService] ❌ Empty MAC provided');
        return null;
      }

      // Clean the MAC - remove all separators
      final cleanMac = mac
          .replaceAll(':', '')
          .replaceAll('-', '')
          .replaceAll(' ', '')
          .replaceAll('.', '')
          .toUpperCase();

      print('[CycleService] 📡 Clean MAC: $cleanMac');

      // Try multiple formats
      final formats = [
        cleanMac,
        _addColons(cleanMac),
        _addDashes(cleanMac),
        _addDots(cleanMac),
      ];

      final uniqueFormats = formats.toSet().toList();

      for (final format in uniqueFormats) {
        print('[CycleService] 🔍 Trying format: "$format"');

        final response = await _supabase
            .from('cycles')
            .select('*, stands!inner(id, name)')
            .eq('mac_address', format)
            .maybeSingle();

        if (response != null) {
          print('[CycleService] ✅ Found cycle with MAC: $format');
          print('[CycleService] 🚲 Cycle ID: ${response['id']}');
          return response;
        }
      }

      // Try partial match
      print('[CycleService] 🔍 Trying partial match...');
      final partialResponse = await _supabase
          .from('cycles')
          .select('*, stands!inner(id, name)')
          .ilike('mac_address', '%$cleanMac%')
          .maybeSingle();

      if (partialResponse != null) {
        print('[CycleService] ✅ Found cycle with partial MAC match');
        print('[CycleService] 🚲 Cycle ID: ${partialResponse['id']}');
        return partialResponse;
      }

      print('[CycleService] ❌ No cycle found with MAC: $mac');
      return null;
    } catch (e) {
      print('[CycleService] ❌ Error getting cycle by MAC: $e');
      return null;
    }
  }

  // ============================================================
  // HELPER: Add colons to MAC
  // ============================================================

  static String _addColons(String mac) {
    if (mac.length != 12) return mac;
    return '${mac.substring(0,2)}:${mac.substring(2,4)}:${mac.substring(4,6)}:${mac.substring(6,8)}:${mac.substring(8,10)}:${mac.substring(10,12)}';
  }

  // ============================================================
  // HELPER: Add dashes to MAC
  // ============================================================

  static String _addDashes(String mac) {
    if (mac.length != 12) return mac;
    return '${mac.substring(0,2)}-${mac.substring(2,4)}-${mac.substring(4,6)}-${mac.substring(6,8)}-${mac.substring(8,10)}-${mac.substring(10,12)}';
  }

  // ============================================================
  // HELPER: Add dots to MAC
  // ============================================================

  static String _addDots(String mac) {
    if (mac.length != 12) return mac;
    return '${mac.substring(0,2)}.${mac.substring(2,4)}.${mac.substring(4,6)}.${mac.substring(6,8)}.${mac.substring(8,10)}.${mac.substring(10,12)}';
  }

  // ============================================================
  // GET STAND BY ID
  // ============================================================

  static Future<Map<String, dynamic>?> getStandById(String standId) async {
    try {
      final response = await _supabase
          .from('stands')
          .select('*, blocks(name)')
          .eq('id', standId)
          .maybeSingle();
      return response;
    } catch (e) {
      print('[CycleService] ❌ Error getting stand: $e');
      return null;
    }
  }

  // ============================================================
  // START RIDE FROM STAND
  // ============================================================

  static Future<Map<String, dynamic>?> startRideFromStand(
      String standId,
      String cycleId,
      ) async {
    try {
      print('[CycleService] =================================');
      print('[CycleService] 🚲 Starting ride from stand');
      print('[CycleService] 📍 Stand: $standId');
      print('[CycleService] 🚲 Cycle: $cycleId');
      print('[CycleService] =================================');

      final userId = _supabase.auth.currentUser?.id;
      final userEmail = _supabase.auth.currentUser?.email;

      if (userId == null || userEmail == null) {
        print('[CycleService] ❌ User not authenticated');
        return null;
      }

      final cycle = await _supabase
          .from('cycles')
          .select('status, stand_id, mac_address')
          .eq('id', cycleId)
          .maybeSingle();

      if (cycle == null) {
        print('[CycleService] ❌ Cycle not found: $cycleId');
        return null;
      }

      if (cycle['status'] != 'available') {
        print('[CycleService] ❌ Cycle not available: ${cycle['status']}');
        return null;
      }

      if (cycle['stand_id'] != standId) {
        print('[CycleService] ❌ Cycle not in this stand');
        return null;
      }

      final String mac = cycle['mac_address'] ?? '';

      if (mac.isEmpty) {
        print('[CycleService] ❌ No MAC address for cycle');
        return null;
      }

      print('[CycleService] 📡 MAC: $mac');

      final activeRide = await _supabase
          .from('rides')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (activeRide != null) {
        print('[CycleService] ❌ User already has active ride');
        return null;
      }

      print('[CycleService] 🔓 Unlocking ESP...');
      final unlockSuccess = await ESPLockService.unlockNative(mac);

      if (!unlockSuccess) {
        print('[CycleService] ❌ ESP unlock failed');
        return null;
      }

      print('[CycleService] ✅ ESP unlocked');

      final rideResponse = await _supabase.from('rides').insert({
        'user_id': userId,
        'cycle_id': cycleId,
        'start_stand_id': standId,
        'start_time': DateTime.now().toIso8601String(),
        'status': 'active',
      }).select();

      print('[CycleService] ✅ Ride created: ${rideResponse.first['id']}');

      await _supabase.from('cycles').update({
        'status': 'in_use',
        'current_user_id': userId,
      }).eq('id', cycleId);

      print('[CycleService] ✅ Cycle updated: $cycleId -> in_use');

      await _supabase.from('stand_activities').insert({
        'stand_id': standId,
        'cycle_id': cycleId,
        'user_id': userId,
        'action': 'unlock',
        'user_email': userEmail,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('[CycleService] ✅ Activity recorded: unlock at $standId');
      print('[CycleService] =================================');

      return rideResponse.first;
    } catch (e) {
      print('[CycleService] ❌ Error starting ride: $e');
      return null;
    }
  }

  // ============================================================
  // END RIDE AT STAND
  // ============================================================

  static Future<bool> endRideAtStand(
      String rideId,
      String cycleId,
      String returnStandId,
      ) async {
    try {
      print('[CycleService] =================================');
      print('[CycleService] 📍 Ending ride at stand');
      print('[CycleService] 🚲 Ride ID: $rideId');
      print('[CycleService] 🚲 Cycle ID: $cycleId');
      print('[CycleService] 📍 Return Stand: $returnStandId');
      print('[CycleService] =================================');

      final userId = _supabase.auth.currentUser?.id;
      final userEmail = _supabase.auth.currentUser?.email;

      if (userId == null || userEmail == null) {
        print('[CycleService] ❌ User not authenticated');
        return false;
      }

      final cycle = await _supabase
          .from('cycles')
          .select('mac_address')
          .eq('id', cycleId)
          .maybeSingle();

      if (cycle == null) {
        print('[CycleService] ❌ Cycle not found');
        return false;
      }

      final String mac = cycle['mac_address'] ?? '';

      if (mac.isEmpty) {
        print('[CycleService] ❌ No MAC address for cycle');
        return false;
      }

      print('[CycleService] 📡 MAC: $mac');

      final ride = await _supabase
          .from('rides')
          .select('*')
          .eq('id', rideId)
          .eq('user_id', userId)
          .maybeSingle();

      if (ride == null) {
        print('[CycleService] ❌ Ride not found: $rideId');
        return false;
      }

      if (ride['status'] == 'completed') {
        print('[CycleService] ⚠️ Ride already completed');
        return true;
      }

      print('[CycleService] 🔒 Locking ESP...');
      final lockSuccess = await ESPLockService.lockNative(mac);

      if (!lockSuccess) {
        print('[CycleService] ❌ ESP lock failed');
        return false;
      }

      print('[CycleService] ✅ ESP locked');

      final startTime = DateTime.parse(ride['start_time']);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inSeconds;

      await _supabase.from('rides').update({
        'end_time': endTime.toIso8601String(),
        'duration': duration,
        'return_stand_id': returnStandId,
        'status': 'completed',
      }).eq('id', rideId);

      print('[CycleService] ✅ Ride completed: $rideId');

      await _supabase.from('cycles').update({
        'status': 'available',
        'current_user_id': null,
        'stand_id': returnStandId,
      }).eq('id', cycleId);

      print('[CycleService] ✅ Cycle moved to: $returnStandId');

      await _supabase.from('stand_activities').insert({
        'stand_id': returnStandId,
        'cycle_id': cycleId,
        'user_id': userId,
        'action': 'lock',
        'user_email': userEmail,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('[CycleService] ✅ Activity recorded: lock at $returnStandId');
      print('[CycleService] =================================');

      return true;
    } catch (e) {
      print('[CycleService] ❌ Error ending ride: $e');
      return false;
    }
  }

  // ============================================================
  // GET ACTIVE RIDE
  // ============================================================

  static Future<Map<String, dynamic>?> getActiveRide() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('rides')
          .select('*, cycles!cycle_id(*), start_stand:start_stand_id(name), return_stand:return_stand_id(name)')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      return response;
    } catch (e) {
      print('[CycleService] Error getting active ride: $e');
      return null;
    }
  }

  // ============================================================
  // GET RIDE HISTORY
  // ============================================================

  static Future<List<Map<String, dynamic>>> getRideHistory() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('rides')
          .select('*, cycles!cycle_id(*), start_stand:start_stand_id(name), return_stand:return_stand_id(name)')
          .eq('user_id', userId)
          .order('start_time', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('[CycleService] Error getting ride history: $e');
      return [];
    }
  }

  // ============================================================
  // GET STAND NAME
  // ============================================================

  static Future<String> getStandName(String standId) async {
    try {
      if (standId.isEmpty) return 'Unknown Stand';
      final response = await _supabase
          .from('stands')
          .select('name')
          .eq('id', standId)
          .maybeSingle();
      return response?['name'] ?? 'Stand $standId';
    } catch (e) {
      return 'Unknown Stand';
    }
  }

  // ============================================================
  // GET CYCLE DETAILS
  // ============================================================

  static Future<Map<String, dynamic>?> getCycleDetails(String cycleId) async {
    try {
      final response = await _supabase
          .from('cycles')
          .select('*, stands!inner(id, name), blocks!inner(name)')
          .eq('id', cycleId)
          .maybeSingle();
      return response;
    } catch (e) {
      print('[CycleService] Error getting cycle details: $e');
      return null;
    }
  }

  // ============================================================
  // VERIFY MAC EXISTS
  // ============================================================

  static Future<bool> verifyMacExists(String mac) async {
    try {
      final result = await getCycleByMac(mac);
      return result != null;
    } catch (e) {
      print('[CycleService] ❌ Error verifying MAC: $e');
      return false;
    }
  }
}