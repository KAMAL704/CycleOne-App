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
  }) : _cycles = cycleService ?? CycleService(),
       _locks = lockService ?? ESPLockService(),
       _pending = pendingStore ?? PendingOperationStore();

  final CycleService _cycles;
  final ESPLockService _locks;
  final PendingOperationStore _pending;

  Future<Map<String, dynamic>> startRideForCycle(
    String cycleId, {
    OperationProgress? progress,
  }) async {
    await reconcilePending();
    progress?.call('Verifying cycle…');
    final cycle = await _cycles.getCycle(cycleId);
    if (cycle['status'] != 'available') {
      throw const AppException('This cycle is not currently available.');
    }
    if (cycle['physical_state'] == 'absent') {
      throw const AppException(
        'This cycle is not physically present at the stand. Refresh inventory and try another cycle.',
      );
    }
    final stand = _asMap(cycle['stands']);
    if (stand == null ||
        cycle['stand_id']?.toString() != stand['id']?.toString()) {
      throw const AppException(
        'This cycle does not have a valid source stand.',
      );
    }
    final active = await _cycles.getActiveRide();
    if (active != null)
      throw const AppException('You already have an active ride.');

    return _startAfterValidation(
      cycle: cycle,
      stand: stand,
      progress: progress,
    );
  }

  Future<Map<String, dynamic>> startRideFromStand({
    required String cycleId,
    required String standId,
    OperationProgress? progress,
  }) async {
    await reconcilePending();
    progress?.call('Verifying selected cycle…');
    final cycle = await _cycles.getCycle(cycleId);
    if (cycle['status'] != 'available' ||
        cycle['stand_id']?.toString() != standId ||
        cycle['physical_state'] == 'absent') {
      throw const AppException(
        'That cycle is no longer available at the selected stand.',
      );
    }
    final stand = await _cycles.getStand(standId);
    final active = await _cycles.getActiveRide();
    if (active != null)
      throw const AppException('You already have an active ride.');
    return _startAfterValidation(
      cycle: cycle,
      stand: stand,
      progress: progress,
    );
  }

  /// Starts an admin-assigned test cycle.  The assignment intentionally
  /// bypasses database inventory checks, but the physical ESP command and
  /// secure MAC verification are still mandatory.
  Future<Map<String, dynamic>> startTestRide({
    required String standId,
    OperationProgress? progress,
  }) async {
    progress?.call('Loading test cycle assignment…');
    final assignment = await _cycles.getActiveTestRide();
    if (assignment == null) {
      throw const AppException('No test cycle is assigned to your account.');
    }
    if (assignment['test_phase'] != 'assigned') {
      throw const AppException('This test cycle is already unlocked. Choose a return stand.');
    }
    final activeRide = await _cycles.getActiveRide();
    if (activeRide != null && activeRide['test_mode'] != true) {
      throw const AppException('Finish your real ride before starting a test cycle.');
    }
    final cycleId = assignment['cycle_id']?.toString();
    if (cycleId == null || cycleId.isEmpty) {
      throw const AppException('The test cycle assignment is invalid.');
    }
    final stand = await _cycles.getStand(standId);
    if (stand['status'] != 'active') {
      throw const AppException('This stand is not accepting test assignments.');
    }
    final endpoint = EspEndpoint.fromStand(stand);
    progress?.call('Unlocking test cycle at ${stand['name']}…');
    try {
      await _locks.transition(
        endpoint: endpoint,
        action: LockAction.unlock,
        cycleId: cycleId,
        standId: standId,
      );
      progress?.call('Recording test unlock…');
      return await _cycles.startTestRide(
        cycleId: cycleId,
        standId: standId,
        espMac: endpoint.mac,
      );
    } on AppException {
      rethrow;
    } finally {
      await _locks.disconnect();
    }
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
    var transitionStarted = false;
    try {
      // Keep the verified ESP connection for the immediately following U/T
      // sequence. One user action must not trigger two Wi-Fi confirmations.
      final inventory = await refreshStandInventory(
        standId,
        progress: progress,
        keepConnection: true,
      );
      if (inventory['present'] != true ||
          inventory['cycle_id']?.toString() != cycleId) {
        throw const AppException(
          'The selected ESP reports that this stand does not contain that cycle.',
        );
      }
      final pending = await _pending.load();
      if (pending != null &&
          !pending.matches(
            PendingOperationType.start,
            cycleId,
            standId,
            userId,
          )) {
        throw const AppException(
          'A previous lock operation still needs recovery. Repeat the same cycle and stand operation first.',
        );
      }
      final endpoint = EspEndpoint.fromStand(stand);
      progress?.call('Connecting to ${stand['name']}…');
      late final HardwareTransition transition;
      transitionStarted = true;
      try {
        transition = await _locks.transition(
          endpoint: endpoint,
          action: LockAction.unlock,
          cycleId: cycleId,
          standId: standId,
        );
      } on AppException catch (error) {
        if (error.code == 'HARDWARE_AMBIGUOUS') {
          await _pending.save(
            PendingOperation(
              type: PendingOperationType.start,
              cycleId: cycleId,
              standId: standId,
              userId: userId,
            ),
          );
        }
        rethrow;
      }
      final existing = await _pending.load();
      if (transition.alreadyInRequestedState &&
          !((existing?.matches(
                PendingOperationType.start,
                cycleId,
                standId,
                userId,
              )) ??
              false)) {
        throw const AppException(
          'This lock is already open. To avoid assigning the wrong cycle, contact campus support.',
        );
      }

      // Persist before the RPC so an app kill after a verified physical change is
      // recoverable without issuing another relay command.
      if (transition.changed) {
        await _pending.save(
          PendingOperation(
            type: PendingOperationType.start,
            cycleId: cycleId,
            standId: standId,
            userId: userId,
          ),
        );
      }
      progress?.call('Starting your ride…');
      try {
        final ride = await _cycles.startRide(
          cycleId: cycleId,
          standId: standId,
          espMac: endpoint.mac,
        );
        await _pending.clear();
        AppLogger.info(
          'RIDE',
          'Ride ${ride['id']} created after verified unlock',
        );
        return ride;
      } on AppException {
        throw const AppException(
          'Hardware operation succeeded but server update failed. Your lock may be open; reconnect to the same stand and use Retry recovery. Do not scan another cycle.',
        );
      }
    } finally {
      // If validation fails after inventory but before transition starts, no
      // operation owns the retained connection.
      if (!transitionStarted) await _locks.disconnect();
    }
  }

  Future<void> returnRideToStand(
    String destinationStandId, {
    OperationProgress? progress,
  }) async {
    await reconcilePending();
    progress?.call('Verifying active ride…');
    final ride = await _cycles.getActiveRide();
    if (ride == null)
      throw const AppException('You do not have an active ride to return.');
    final cycleId = ride['cycle_id'].toString();
    final rideId = ride['id'].toString();
    final stand = await _cycles.getStand(destinationStandId);
    if (stand['status'] != 'active')
      throw const AppException('This stand is not accepting returns.');
    var transitionStarted = false;
    try {
      final destinationInventory = await refreshStandInventory(
        destinationStandId,
        progress: progress,
        keepConnection: true,
      );
      if (destinationInventory['present'] == true &&
          (stand['capacity'] as num?)?.toInt() == 1) {
        throw const AppException(
          'This stand already contains a cycle. Choose another empty stand.',
        );
      }
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw const AppException('Please sign in again.');
      final pending = await _pending.load();
      if (pending != null &&
          !pending.matches(
            PendingOperationType.end,
            cycleId,
            destinationStandId,
            userId,
          )) {
        throw const AppException(
          'A previous return lock operation still needs recovery. Repeat the same destination stand operation first.',
        );
      }
      final endpoint = EspEndpoint.fromStand(stand);

      progress?.call('Connecting to ${stand['name']}…');
      late final HardwareTransition transition;
      transitionStarted = true;
      try {
        transition = await _locks.transition(
          endpoint: endpoint,
          action: LockAction.lock,
          cycleId: cycleId,
          standId: destinationStandId,
        );
      } on AppException catch (error) {
        if (error.code == 'HARDWARE_AMBIGUOUS') {
          await _pending.save(
            PendingOperation(
              type: PendingOperationType.end,
              cycleId: cycleId,
              standId: destinationStandId,
              userId: userId,
              rideId: rideId,
            ),
          );
        }
        rethrow;
      }
      final existing = await _pending.load();
      if (transition.alreadyInRequestedState &&
          !((existing?.matches(
                PendingOperationType.end,
                cycleId,
                destinationStandId,
                userId,
              )) ??
              false)) {
        throw const AppException(
          'This destination lock is already closed. Your ride is still active; contact campus support.',
        );
      }
      if (transition.changed) {
        await _pending.save(
          PendingOperation(
            type: PendingOperationType.end,
            cycleId: cycleId,
            standId: destinationStandId,
            userId: userId,
            rideId: rideId,
          ),
        );
      }
      progress?.call('Completing return…');
      try {
        await _cycles.endRide(
          rideId: rideId,
          cycleId: cycleId,
          destinationStandId: destinationStandId,
          espMac: endpoint.mac,
        );
        await _pending.clear();
        AppLogger.info('RIDE', 'Ride $rideId completed after verified lock');
      } on AppException {
        throw const AppException(
          'Hardware operation succeeded but server update failed. Your ride is still active in CycleOne; reconnect to this same stand and use Retry recovery. Do not unlock it again.',
        );
      }
    } finally {
      if (!transitionStarted) await _locks.disconnect();
    }
  }

  /// Completes an admin test assignment after a real destination ESP confirms
  /// the lock.  Test mode does not update cycles/rides or enforce DB capacity;
  /// the selected physical stand and its MAC are still verified server-side.
  Future<void> returnTestRideToStand(
    String destinationStandId, {
    OperationProgress? progress,
  }) async {
    progress?.call('Verifying test cycle…');
    final assignment = await _cycles.getActiveTestRide();
    if (assignment == null || assignment['test_phase'] != 'unlocked') {
      throw const AppException('No unlocked test cycle is active.');
    }
    final cycleId = assignment['cycle_id']?.toString();
    if (cycleId == null || cycleId.isEmpty) {
      throw const AppException('The test cycle assignment is invalid.');
    }
    final stand = await _cycles.getStand(destinationStandId);
    if (stand['status'] != 'active') {
      throw const AppException('This stand is not accepting test returns.');
    }
    final endpoint = EspEndpoint.fromStand(stand);
    progress?.call('Locking test cycle at ${stand['name']}…');
    try {
      await _locks.transition(
        endpoint: endpoint,
        action: LockAction.lock,
        cycleId: cycleId,
        standId: destinationStandId,
      );
      progress?.call('Completing test return…');
      await _cycles.endTestRide(
        cycleId: cycleId,
        destinationStandId: destinationStandId,
        espMac: endpoint.mac,
      );
    } on AppException {
      rethrow;
    } finally {
      await _locks.disconnect();
    }
  }

  /// Retrying only commits a matching operation whose hardware state is already
  /// known. It never pulses the relay a second time.
  Future<bool> hasPendingRecovery() async => await reconcilePending() != null;

  /// Verifies the exact stand BSSID and asks the ESP for physical cycle
  /// presence. Ride operations may retain the connection for their following
  /// U/T sequence; standalone inventory checks close it automatically.
  Future<Map<String, dynamic>> refreshStandInventory(
    String standId, {
    OperationProgress? progress,
    bool keepConnection = false,
  }) async {
    final stand = await _cycles.getStand(standId);
    final endpoint = EspEndpoint.fromStand(stand);
    progress?.call('Checking ${stand['name']} inventory…');
    try {
      final physical = await _locks.readPresence(
        endpoint,
        keepConnection: keepConnection,
      );
      return await _cycles.syncCyclePresence(
        standId: standId,
        espMac: endpoint.mac,
        present: physical.cyclePresent,
      );
    } catch (_) {
      if (keepConnection) await _locks.disconnect();
      rethrow;
    }
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
        if (active?['cycle_id']?.toString() == pending.cycleId &&
            cycle['status'] == 'in_use') {
          await _pending.clear();
          return null;
        }
      } else {
        final active = await _cycles.getActiveRide();
        if (active == null &&
            cycle['status'] == 'available' &&
            cycle['stand_id']?.toString() == pending.standId) {
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

  Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
}
