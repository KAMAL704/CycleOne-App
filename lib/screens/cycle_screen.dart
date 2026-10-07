import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/errors/app_exception.dart';
import '../models/qr_payload.dart';
import '../providers/auth_provider.dart';
import '../providers/cycle_provider.dart';
import '../services/cycle_service.dart';
import '../services/ride_operation_service.dart';
import '../widgets/stand_selector_bottom_sheet.dart';
import 'qr_scanner_screen.dart';

class CycleScreen extends StatefulWidget {
  const CycleScreen({super.key});

  @override
  State<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends State<CycleScreen> {
  final _operations = RideOperationService();
  final _cycles = CycleService();
  bool _busy = false;
  String _progress = '';
  Map<String, dynamic>? _activeRide;
  bool _loadingRide = true;
  bool _hasRecovery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loadingRide = true);
    try {
      final results = await Future.wait([
        _cycles.getActiveRide(),
        _operations.hasPendingRecovery(),
      ]);
      if (mounted) {
        setState(() {
          _activeRide = results[0] as Map<String, dynamic>?;
          _hasRecovery = results[1] as bool;
        });
      }
    } on AppException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _loadingRide = false);
    }
  }

  Future<void> _scanCycle() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (!mounted || raw == null) return;
    try {
      final payload = QrPayload.parse(raw, expectedKind: QrKind.cycle);
      final cycleId = payload.isMac
          ? await _cycles.resolveCycleIdFromMac(payload.id)
          : payload.id;
      await _run(
        () => _operations.startRideForCycle(cycleId, progress: _setProgress),
        success: 'Ride started. The cycle is unlocked.',
      );
    } on AppException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _selectCycle() async {
    final selection = await showStandSelectorBottomSheet(
      context,
      forReturn: false,
    );
    if (!mounted || selection == null) return;
    await _run(
      () => _operations.startRideFromStand(
        cycleId: selection.cycleId!,
        standId: selection.standId,
        progress: _setProgress,
      ),
      success: 'Ride started. The cycle is unlocked.',
    );
  }

  Future<void> _scanStand() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (!mounted || raw == null) return;
    try {
      final payload = QrPayload.parse(raw, expectedKind: QrKind.stand);
      await _returnTo(payload.id);
    } on AppException catch (error) {
      // A rider may scan the same cycle QR while returning. A cycle QR does
      // not identify the destination stand, so use it as a shortcut into the
      // normal return-stand picker instead of showing a confusing type error.
      var isCycleQr = false;
      try {
        QrPayload.parse(raw, expectedKind: QrKind.cycle);
        isCycleQr = true;
      } on AppException {
        // It is a different QR type; keep the original scanner error below.
      }
      if (isCycleQr) {
        _message('Cycle QR recognized. Choose the return stand.');
        await _selectStand();
      } else {
        _message(error.message);
      }
    }
  }

  Future<void> _selectStand() async {
    final selection = await showStandSelectorBottomSheet(
      context,
      forReturn: true,
    );
    if (!mounted || selection == null) return;
    await _returnTo(selection.standId);
  }

  Future<void> _selectTestStand() async {
    final selection = await showStandSelectorBottomSheet(
      context,
      forReturn: true,
    );
    if (!mounted || selection == null) return;
    await _run(
      () => _operations.startTestRide(
        standId: selection.standId,
        progress: _setProgress,
      ),
      success: 'Test cycle assigned and unlocked through the selected ESP.',
    );
  }

  Future<void> _returnTo(String standId) => _run(
    () => _activeRide?['test_mode'] == true
        ? _operations.returnTestRideToStand(standId, progress: _setProgress)
        : _operations.returnRideToStand(standId, progress: _setProgress),
    success: _activeRide?['test_mode'] == true
        ? 'Test cycle locked through the ESP and test assignment completed.'
        : 'Cycle returned and your ride is complete.',
  );

  void _setProgress(String value) {
    if (mounted) setState(() => _progress = value);
  }

  Future<void> _run(
    Future<Object?> Function() action, {
    required String success,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 'Preparing…';
    });
    try {
      final result = await action();
      if (result is Map) {
        context.read<CycleProvider>().allocateCycle(
          result['cycle_id'].toString(),
          result['id'].toString(),
        );
      } else {
        context.read<CycleProvider>().returnCycle();
      }
      await context.read<CycleProvider>().refreshCycle();
      await _refresh();
      if (mounted) _message(success, color: Colors.green.shade700);
    } on AppException catch (error) {
      if (mounted) _message(error.message, color: Colors.red.shade700);
    } catch (_) {
      if (mounted)
        _message(
          'Something unexpected interrupted the operation. No database success was assumed.',
          color: Colors.red.shade700,
        );
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _progress = '';
        });
    }
  }

  void _message(String text, {Color? color}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), backgroundColor: color));

  @override
  Widget build(BuildContext context) {
    final active = _activeRide;
    final activeCycle = active?['cycles'] is Map
        ? Map<String, dynamic>.from(active!['cycles'] as Map)
        : null;
    final isTestRide = active?['test_mode'] == true;
    final testPhase = active?['test_phase']?.toString() ?? 'assigned';
    return Scaffold(
      appBar: AppBar(
        title: const Text('CycleOne'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Hello, ${context.watch<AuthProvider>().profile['name'] ?? 'Student'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              active == null
                  ? 'Ready when you are.'
                  : isTestRide
                  ? 'Admin test cycle · ${testPhase == 'assigned' ? 'ready to unlock' : 'in progress'}.'
                  : 'Your ride is in progress.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            if (_loadingRide)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              _rideCard(active, activeCycle),
            if (_hasRecovery) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.amber.shade50,
                child: const ListTile(
                  leading: Icon(Icons.warning_amber_rounded),
                  title: Text('Recovery required'),
                  subtitle: Text(
                    'A verified lock action still needs a server update. Repeat the same scan or selection only; CycleOne will not pulse the lock again.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_busy) ...[
              LinearProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(_progress, textAlign: TextAlign.center),
            ] else if (active == null) ...[
              FilledButton.icon(
                onPressed: _scanCycle,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan cycle QR'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _selectCycle,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Choose from a stand'),
              ),
            ] else if (isTestRide && testPhase == 'assigned') ...[
              FilledButton.icon(
                onPressed: _selectTestStand,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Choose ESP and unlock test cycle'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _scanStand,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan return stand QR'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _selectStand,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Choose a return stand'),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              isTestRide
                  ? 'Test mode still requires the selected physical ESP to confirm every unlock and return. It does not change real inventory or ride history.'
                  : 'For your safety, CycleOne only updates your ride after the selected physical lock confirms the change.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideCard(
    Map<String, dynamic>? active,
    Map<String, dynamic>? cycle,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: active == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.pedal_bike, size: 34),
                SizedBox(height: 8),
                Text(
                  'No active ride',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text('Scan a CycleOne cycle to begin.'),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined),
                    SizedBox(width: 8),
                    Text(
                      active['test_mode'] == true
                          ? 'Test cycle assigned'
                          : 'Ride in progress',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Cycle: ${cycle?['cycle_number'] ?? active['cycle_id']}'),
                if (active['test_mode'] == true)
                  Text(
                    active['test_phase'] == 'assigned'
                        ? 'Choose any active ESP stand to assign and unlock this test cycle.'
                        : 'Unlocked for test. Choose any active return stand.',
                  ),
                Text(
                  '${active['test_mode'] == true ? 'Assigned' : 'Started'}: ${active['started_at'] ?? '—'}',
                ),
              ],
            ),
    ),
  );
}
