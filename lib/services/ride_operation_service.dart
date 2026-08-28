import '../core/errors/app_exception.dart';
import '../core/logging/app_logger.dart';
import '../models/esp_endpoint.dart';
import 'cycle_service.dart';
import 'esp_lock_service.dart';
import 'pending_operation_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef OperationProgress = void Function(String message);

/// Coordinates the hardware-first lifecycle. This deliberately contains the
/// ordering logic rather than scattering it across widgets.
class RideOperationService {
  RideOperationService({
    CycleService? cycleService,
    ESPLockService? lockService,
    PendingOperationStore? pendingStore,
  })  : _cycles = cycleService ?? CycleService(),
        _locks = lockService ?? ESPLockService(),
        _pending = pendingStore ?? PendingOperationStore();

  final CycleService _cycles;
  final ESPLockService _locks;
  final PendingOperationStore _pending;

  Future<Map<String, dynamic>> startRideForCycle(String cycleId, {OperationProgress? progress}) async {
    await reconcilePending();
    progress?.call('Verifying cycle…');
    final cycle = await _cycles.getCycle(cycleId);
    if (cycle['status'] != 'available') {
      throw const AppException('This cycle is not currently available.');
    }
    if (cycle['physical_state'] == 'absent') {
      throw const AppException('This cycle is not physically present at the stand. Refresh inventory and try another cycle.');
    }
    final stand = _asMap(cycle['stands']);
    if (stand == null || cycle['stand_id']?.toString() != stand['id']?.toString()) {
      throw const AppException('This cycle does not have a valid source stand.');
    }
    final active = await _cycles.getActiveRide();
    if (active != null) throw const AppException('You already have an active ride.');

    return _startAfterValidation(cycle: cycle, stand: stand, progress: progress);
  }

  Future<Map<String, dynamic>> startRideFromStand({
    required String cycleId,
    required String standId,
    OperationProgress? progress,
  }) async {
    await reconcilePending();
    progress?.call('Verifying selected cycle…');
    final cycle = await _cycles.getCycle(cycleId);
    if (cycle['status'] != 'available' || cycle['stand_id']?.toString() != standId || cycle['physical_state'] == 'absent') {
      throw const AppException('That cycle is no longer available at the selected stand.');
    }
    final stand = await _cycles.getStand(standId);
    final active = await _cycles.getActiveRide();
    if (active != null) throw const AppException('You already have an active ride.');
    return _startAfterValidation(cycle: cycle, stand: stand, progress: progress);
  }

  Future<Map<String, dynamic>> _startAfterValidation({
    required Map<String, dynamic> cycle,
    required Map<String, dynamic> stand,
    OperationProgress? progress,
  }) async {
    final cycleId = cycle['id'].toString();
    final standId = stand['id'].toString();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw const AppException('Please sign in again.');
    final inventory = await refreshStandInventory(standId, progress: progress);
    if (inventory['present'] != true || inventory['cycle_id']?.toString() != cycleId) {
      throw const AppException('The selected ESP reports that this stand does not contain that cycle.');
    }
    final pending = await _pending.load();
    if (pending != null && !pending.matches(PendingOperationType.start, cycleId, standId, userId)) {
      throw const AppException('A previous lock operation still needs recovery. Repeat the same cycle and stand operation first.');
    }
    final endpoint = EspEndpoint.fromStand(stand);
    progress?.call('Connecting to ${stand['name']}…');
    late final HardwareTransition transition;
    try {
      transition = await _locks.transition(
        endpoint: endpoint,
        action: LockAction.unlock,
        cycleId: cycleId,
        standId: standId,
      );
    } on AppException catch (error) {
      if (error.code == 'HARDWARE_AMBIGUOUS') {
        await _pending.save(PendingOperation(type: PendingOperationType.start, cycleId: cycleId, standId: standId, userId: userId));
      }
      rethrow;
    }
    final existing = await _pending.load();
    if (transition.alreadyInRequestedState && !((existing?.matches(PendingOperationType.start, cycleId, standId, userId)) ?? false)) {
      throw const AppException('This lock is already open. To avoid assigning the wrong cycle, contact campus support.');
    }

    // Persist before the RPC so an app kill after a verified physical change is
    // recoverable without issuing another relay command.
    if (transition.changed) {
      await _pending.save(PendingOperation(type: PendingOperationType.start, cycleId: cycleId, standId: standId, userId: userId));
    }
    progress?.call('Starting your ride…');
    try {
      final ride = await _cycles.startRide(cycleId: cycleId, standId: standId, espMac: endpoint.mac);
      await _pending.clear();
      AppLogger.info('RIDE', 'Ride ${ride['id']} created after verified unlock');
      return ride;
    } on AppException {
      throw const AppException(
        'Hardware operation succeeded but server update failed. Your lock may be open; reconnect to the same stand and use Retry recovery. Do not scan another cycle.',
      );
    }
  }

  Future<void> returnRideToStand(String destinationStandId, {OperationProgress? progress}) async {
    await reconcilePending();
    progress?.call('Verifying active ride…');
    final ride = await _cycles.getActiveRide();
    if (ride == null) throw const AppException('You do not have an active ride to return.');
    final cycleId = ride['cycle_id'].toString();
    final rideId = ride['id'].toString();
    final stand = await _cycles.getStand(destinationStandId);
    if (stand['status'] != 'active') throw const AppException('This stand is not accepting returns.');
    final destinationInventory = await refreshStandInventory(destinationStandId, progress: progress);
    if (destinationInventory['present'] == true && (stand['capacity'] as num?)?.toInt() == 1) {
      throw const AppException('This stand already contains a cycle. Choose another empty stand.');
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) throw const AppException('Please sign in again.');
    final pending = await _pending.load();
    if (pending != null && !pending.matches(PendingOperationType.end, cycleId, destinationStandId, userId)) {
      throw const AppException('A previous return lock operation still needs recovery. Repeat the same destination stand operation first.');
    }
    final endpoint = EspEndpoint.fromStand(stand);

    progress?.call('Connecting to ${stand['name']}…');
    late final HardwareTransition transition;
    try {
      transition = await _locks.transition(
        endpoint: endpoint,
        action: LockAction.lock,
        cycleId: cycleId,
        standId: destinationStandId,
      );
    } on AppException catch (error) {
      if (error.code == 'HARDWARE_AMBIGUOUS') {
        await _pending.save(PendingOperation(type: PendingOperationType.end, cycleId: cycleId, standId: destinationStandId, userId: userId, rideId: rideId));
      }
      rethrow;
    }
    final existing = await _pending.load();
    if (transition.alreadyInRequestedState && !((existing?.matches(PendingOperationType.end, cycleId, destinationStandId, userId)) ?? false)) {
      throw const AppException('This destination lock is already closed. Your ride is still active; contact campus support.');
    }
    if (transition.changed) {
      await _pending.save(PendingOperation(
        type: PendingOperationType.end,
        cycleId: cycleId,
        standId: destinationStandId,
        userId: userId,
        rideId: rideId,
      ));
    }
    progress?.call('Completing return…');
    try {
      await _cycles.endRide(rideId: rideId, cycleId: cycleId, destinationStandId: destinationStandId, espMac: endpoint.mac);
      await _pending.clear();
      AppLogger.info('RIDE', 'Ride $rideId completed after verified lock');
    } on AppException {
      throw const AppException(
        'Hardware operation succeeded but server update failed. Your ride is still active in CycleOne; reconnect to this same stand and use Retry recovery. Do not unlock it again.',
      );
    }
  }

  /// Retrying only commits a matching operation whose hardware state is already
  /// known. It never pulses the relay a second time.
  Future<bool> hasPendingRecovery() async => await reconcilePending() != null;

  /// Verifies the exact stand BSSID and asks the ESP for physical cycle
  /// presence. This is called before showing a stand's available cycles.
  Future<Map<String, dynamic>> refreshStandInventory(String standId, {OperationProgress? progress}) async {
    final stand = await _cycles.getStand(standId);
    final endpoint = EspEndpoint.fromStand(stand);
    progress?.call('Checking ${stand['name']} inventory…');
    final physical = await _locks.readPresence(endpoint);
    return _cycles.syncCyclePresence(standId: standId, espMac: endpoint.mac, present: physical.cyclePresent);
  }

  /// Clears a local recovery marker when the server commit actually completed
  /// before the app was killed. It never sends a hardware command.
  Future<PendingOperation?> reconcilePending() async {
    final pending = await _pending.load();
    if (pending == null) return null;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || pending.userId != userId) {
      await _pending.clear();
      return null;
    }
    try {
      final cycle = await _cycles.getCycle(pending.cycleId);
      if (pending.type == PendingOperationType.start) {
        final active = await _cycles.getActiveRide();
        if (active?['cycle_id']?.toString() == pending.cycleId && cycle['status'] == 'in_use') {
          await _pending.clear();
          return null;
        }
      } else {
        final active = await _cycles.getActiveRide();
        if (active == null && cycle['status'] == 'available' && cycle['stand_id']?.toString() == pending.standId) {
          await _pending.clear();
          return null;
        }
      }
    } catch (_) {
      // Keep the marker when the server is unavailable; the user must retry
      // the same operation once connectivity returns.
    }
    return pending;
  }

  Map<String, dynamic>? _asMap(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;
}
