import 'package:flutter/foundation.dart';

import '../core/logging/app_logger.dart';
import '../services/cycle_service.dart';

class CycleProvider extends ChangeNotifier {
  CycleProvider({CycleService? service}) : _service = service ?? CycleService();

  final CycleService _service;
  String? _currentCycleId;
  String? _currentRideId;
  bool _isLoading = true;
  bool _refreshing = false;

  bool get hasCycle => _currentCycleId != null && _currentRideId != null;
  String? get currentCycleId => _currentCycleId;
  String? get currentRideId => _currentRideId;
  bool get isLoading => _isLoading;

  Future<void> refreshCycle() async {
    if (_refreshing) return;
    _refreshing = true;
    _isLoading = true;
    notifyListeners();
    try {
      final ride = await _service.getActiveRide();
      _currentRideId = ride?['id']?.toString();
      _currentCycleId = ride?['cycle_id']?.toString();
      AppLogger.info('RIDE', ride == null ? 'No active ride' : 'Active ride loaded');
    } catch (error, stackTrace) {
      // Preserve a known active ride during a temporary network outage.
      AppLogger.error('RIDE', error, stackTrace);
    } finally {
      _isLoading = false;
      _refreshing = false;
      notifyListeners();
    }
  }

  void allocateCycle(String cycleId, String rideId) {
    _currentCycleId = cycleId;
    _currentRideId = rideId;
    notifyListeners();
  }

  void returnCycle() {
    _currentCycleId = null;
    _currentRideId = null;
    notifyListeners();
  }

  void reset() => returnCycle();
}
