import 'package:supabase_flutter/supabase_flutter.dart';

class StandService {
  // ✅ Get all blocks (NEW)
  static Future<List<Map<String, dynamic>>> getBlocks() async {
    try {
      final response = await Supabase.instance.client
          .from('blocks')
          .select('*')
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching blocks: $e');
      return [];
    }
  }

  // Get all stands with their cycles
  static Future<List<Map<String, dynamic>>> getStands() async {
    try {
      final response = await Supabase.instance.client
          .from('stands')
          .select('*, blocks(name), cycles!stand_id(id, status)')
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching stands: $e');
      return [];
    }
  }

  // Get stands for a specific block
  static Future<List<Map<String, dynamic>>> getStandsForBlock(String blockId) async {
    try {
      final response = await Supabase.instance.client
          .from('stands')
          .select('*, cycles!stand_id(id, status)')
          .eq('block_id', blockId)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching stands for block: $e');
      return [];
    }
  }

  // Get available cycles for a stand
  static Future<List<Map<String, dynamic>>> getCyclesForStand(String standId) async {
    try {
      final response = await Supabase.instance.client
          .from('cycles')
          .select('*')
          .eq('stand_id', standId)
          .eq('status', 'available');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching cycles for stand: $e');
      return [];
    }
  }

  // Get stand activities (last 5)
  static Future<List<Map<String, dynamic>>> getStandActivities(String standId) async {
    try {
      final response = await Supabase.instance.client
          .from('stand_activities')
          .select('*')
          .eq('stand_id', standId)
          .order('timestamp', ascending: false)
          .limit(5);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching activities: $e');
      return [];
    }
  }

  // Record activity
  static Future<void> recordActivity({
    required String standId,
    required String cycleId,
    required String action,
    required String userId,
    required String userEmail,
  }) async {
    try {
      await Supabase.instance.client.from('stand_activities').insert({
        'stand_id': standId,
        'cycle_id': cycleId,
        'user_id': userId,
        'action': action,
        'user_email': userEmail,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error recording activity: $e');
    }
  }

  // Allot cycle to user
  static Future<void> allotCycleToUser(String cycleId, String userId) async {
    try {
      await Supabase.instance.client.from('cycles').update({
        'status': 'in_use',
        'current_user_id': userId,
      }).eq('id', cycleId);
    } catch (e) {
      print('Error allotting cycle: $e');
    }
  }

  // Make cycle available
  static Future<void> makeCycleAvailable(String cycleId) async {
    try {
      await Supabase.instance.client.from('cycles').update({
        'status': 'available',
        'current_user_id': null,
      }).eq('id', cycleId);
    } catch (e) {
      print('Error making cycle available: $e');
    }
  }

  // Get stand ID for a cycle
  static Future<String?> getStandIdForCycle(String cycleId) async {
    try {
      final response = await Supabase.instance.client
          .from('cycles')
          .select('stand_id')
          .eq('id', cycleId)
          .maybeSingle();
      return response?['stand_id'];
    } catch (e) {
      print('Error getting stand ID: $e');
      return null;
    }
  }
}