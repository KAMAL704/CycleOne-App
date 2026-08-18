import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CycleProvider extends ChangeNotifier {
  String? _currentCycleId;
  String? _currentRideId;
  bool _isLoading = true;
  bool _isRefreshing = false;

  bool get hasCycle => _currentCycleId != null && _currentRideId != null;
  String? get currentCycleId => _currentCycleId;
  String? get currentRideId => _currentRideId;
  bool get isLoading => _isLoading;

  CycleProvider() {
    _loadUserState();
  }

  Future<void> _loadUserState() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    _isLoading = true;
    notifyListeners();

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        _currentCycleId = null;
        _currentRideId = null;
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
        return;
      }

      final rideResponse = await Supabase.instance.client
          .from('rides')
          .select('id, cycle_id')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (rideResponse != null) {
        _currentRideId = rideResponse['id'];
        _currentCycleId = rideResponse['cycle_id'];
        print('✅ Active ride loaded: $_currentCycleId');
      } else {
        _currentCycleId = null;
        _currentRideId = null;
        print('✅ No active ride');
      }
    } catch (e) {
      print('❌ Error loading user state: $e');
      _currentCycleId = null;
      _currentRideId = null;
    }
    _isLoading = false;
    _isRefreshing = false;
    print('📢 Notifying listeners - hasCycle: $hasCycle');
    notifyListeners();
  }

  void allocateCycle(String cycleId, String rideId) {
    print('🔄 Allocating cycle: $cycleId, ride: $rideId');
    _currentCycleId = cycleId;
    _currentRideId = rideId;
    print('✅ Cycle allocated - hasCycle: $hasCycle');
    notifyListeners();
  }

  void returnCycle() {
    print('🔄 Clearing provider state...');
    print('   Before: cycle=$_currentCycleId, ride=$_currentRideId');
    _currentCycleId = null;
    _currentRideId = null;
    print('   After: cycle=$_currentCycleId, ride=$_currentRideId');
    print('   hasCycle: $hasCycle');
    print('📢 Notifying listeners');
    notifyListeners();
  }

  void reset() {
    print('🔄 Resetting provider');
    _currentCycleId = null;
    _currentRideId = null;
    notifyListeners();
  }

  Future<void> refreshCycle() async {
    if (_isRefreshing) {
      print('⏳ Refresh already in progress');
      return;
    }
    print('🔄 Refreshing cycle state...');
    await _loadUserState();
  }
}