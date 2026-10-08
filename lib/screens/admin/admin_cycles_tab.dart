import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../models/esp_endpoint.dart';
import '../../services/ride_operation_service.dart';

class AdminCyclesTab extends StatefulWidget {
  const AdminCyclesTab({super.key});

  @override
  State<AdminCyclesTab> createState() => _AdminCyclesTabState();
}

class _AdminCyclesTabState extends State<AdminCyclesTab> {
  final _client = Supabase.instance.client;
  final _operations = RideOperationService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _cycles = const [];
  List<Map<String, dynamic>> _stands = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleCycles {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _cycles;
    return _cycles.where((cycle) {
      final stand = cycle['stands'];
      final searchable = [
        cycle['cycle_number'],
        cycle['status'],
        cycle['physical_state'],
        cycle['esp_mac'],
        if (stand is Map) stand['name'],
        if (stand is Map) stand['esp_mac'],
      ].whereType<Object>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final results = await Future.wait([
        _client
            .from('cycles')
            .select(
              'id, cycle_number, qr_code, esp_mac, status, stand_id, physical_state, stands(name, esp_mac)',
            )
            .order('cycle_number'),
        _client.from('stands').select('id, name, status').order('name'),
      ]);
      if (mounted)
        setState(() {
          _cycles = List<Map<String, dynamic>>.from(results[0] as List);
          _stands = List<Map<String, dynamic>>.from(results[1] as List);
        });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load cycles: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCycle() async {
    final activeStands = _activeStands;
    if (activeStands.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable and configure at least one stand before adding a cycle.',
            ),
          ),
        );
      return;
    }
    final number = TextEditingController();
    String? standId;
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add cycle'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: number,
                  decoration: const InputDecoration(labelText: 'Cycle number'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: standId,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Colors.black87),
                  decoration: const InputDecoration(
                    labelText: 'Starting stand',
                  ),
                  items: activeStands
                      .map(
                        (stand) => DropdownMenuItem(
                          value: stand['id'].toString(),
                          child: Text(stand['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => standId = value),
                  validator: (value) => value == null ? 'Choose a stand' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate())
                  Navigator.pop(dialogContext, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || standId == null) return;
    try {
      await _client.rpc(
        'admin_add_cycle',
        params: {'p_cycle_number': number.text.trim(), 'p_stand_id': standId},
      );
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError('Could not add cycle', error))),
        );
    } finally {
      number.dispose();
    }
  }

  Future<void> _setStatus(Map<String, dynamic> cycle, String status) async {
    if (cycle['status'] == 'in_use') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'An in-use cycle cannot be changed while a ride is active.',
          ),
        ),
      );
      return;
    }
    try {
      if (status == 'disabled') {
        await _client.rpc(
          'admin_remove_cycle',
          params: {'p_cycle_id': cycle['id']},
        );
      } else {
        final standId = cycle['stand_id']?.toString();
        if (standId == null || standId.isEmpty)
          throw const FormatException('Assign the cycle to a stand first.');
        await _client.rpc(
          'admin_assign_cycle',
          params: {'p_cycle_id': cycle['id'], 'p_stand_id': standId},
        );
      }
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError('Could not update cycle', error)),
          ),
        );
    }
  }

  Future<void> _move(Map<String, dynamic> cycle) async {
    if (cycle['status'] == 'in_use') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'An in-use cycle cannot be moved while a ride is active.',
          ),
        ),
      );
      return;
    }
    final activeStands = _activeStands;
    if (activeStands.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No active stands are available. Enable a configured stand first.',
            ),
          ),
        );
      return;
    }
    String? standId = cycle['stand_id']?.toString();
    if (standId == null ||
        !activeStands.any((stand) => stand['id'].toString() == standId)) {
      standId = activeStands.first['id'].toString();
    }
    final selected = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Assign stand'),
          content: DropdownButton<String>(
            value: standId,
            isExpanded: true,
            dropdownColor: Colors.white,
            style: const TextStyle(color: Colors.black87),
            items: activeStands
                .map(
                  (stand) => DropdownMenuItem(
                    value: stand['id'].toString(),
                    child: Text(stand['name'].toString()),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => standId = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (selected != true || standId == null) return;
    try {
      await _client.rpc(
        'admin_assign_cycle',
        params: {'p_cycle_id': cycle['id'], 'p_stand_id': standId},
      );
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError('Could not move cycle', error)),
          ),
        );
    }
  }

  Future<void> _remove(Map<String, dynamic> cycle) =>
      _setStatus(cycle, 'disabled');

  Future<void> _clearStaleAssignment(Map<String, dynamic> cycle) async {
    if (cycle['status'] == 'in_use') return;
    try {
      // An ESP-confirmed absent row is historical inventory, not a parked
      // cycle. Keep the cycle record, but clear the guessed stand so an admin
      // can assign its real location and verify that stand's ESP.
      await _client.rpc(
        'admin_assign_cycle',
        params: {'p_cycle_id': cycle['id'], 'p_stand_id': null},
      );
      await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _friendlyError('Could not clear stale assignment', error),
            ),
          ),
        );
    }
  }

  Future<void> _verifyInventory(Map<String, dynamic> cycle) async {
    final standId = cycle['stand_id']?.toString();
    if (standId == null || standId.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assign this cycle to an active stand first.'),
          ),
        );
      return;
    }
    if (cycle['status'] == 'in_use') {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'An in-use cycle cannot be verified from the admin inventory screen.',
            ),
          ),
        );
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final inventory = await _operations.refreshStandInventory(standId);
      await _load();
      if (!mounted) return;
      final present = inventory['present'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            present
                ? 'ESP confirmed the cycle. It is now available.'
                : 'ESP reported no cycle at this stand.',
          ),
        ),
      );
    } on AppException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not verify ESP inventory: $error')),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _renameCycle(Map<String, dynamic> cycle) async {
    final controller = TextEditingController(
      text: cycle['cycle_number']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Edit cycle name'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Cycle number / name',
              hintText: 'Example: 300',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a cycle name'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) {
      controller.dispose();
      return;
    }
    try {
      await _client.rpc(
        'admin_rename_cycle',
        params: {
          'p_cycle_id': cycle['id'],
          'p_cycle_number': controller.text.trim(),
        },
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError('Could not rename cycle', error)),
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  List<Map<String, dynamic>> get _activeStands =>
      _stands.where((stand) => stand['status'] == 'active').toList();

  String _friendlyError(String action, Object error) {
    if (error is PostgrestException &&
        error.message.toLowerCase().contains('stand is not active')) {
      return '$action: selected stand is disabled. Enable and configure that stand first.';
    }
    if (error is PostgrestException &&
        error.message.toLowerCase().contains('stand capacity is full')) {
      return '$action: this stand already has its one cycle slot occupied.';
    }
    return '$action: $error';
  }

  String? _cycleQrData(Map<String, dynamic> cycle) {
    final directMac = EspEndpoint.normalizeMac(
      cycle['esp_mac']?.toString() ?? '',
    );
    if (directMac.isNotEmpty) return directMac.replaceAll(':', '');
    final stand = cycle['stands'];
    if (stand is Map) {
      final standMac = EspEndpoint.normalizeMac(
        stand['esp_mac']?.toString() ?? '',
      );
      if (standMac.isNotEmpty) return standMac.replaceAll(':', '');
    }
    return null;
  }

  void _showQr(Map<String, dynamic> cycle) {
    final qrData = _cycleQrData(cycle);
    if (qrData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This cycle has no valid ESP MAC yet. Verify or assign its stand first.',
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('QR · ${cycle['cycle_number']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: qrData, size: 220),
            const SizedBox(height: 12),
            SelectableText(qrData, textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : _addCycle,
      icon: const Icon(Icons.add),
      label: const Text('Cycle'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search cycles',
                    hintText: 'Cycle number, stand, MAC or status',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.clear),
                          ),
                    filled: true,
                    fillColor: Colors.white.withAlpha(235),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: _visibleCycles.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(36),
                              child: Text(
                                _cycles.isEmpty
                                    ? 'No cycles found.'
                                    : 'No cycles match your search.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: _visibleCycles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final cycle = _visibleCycles[index];
                            final stand = cycle['stands'] is Map
                                ? (cycle['stands'] as Map)['name']
                                : 'Unassigned';
                            final status = cycle['status'].toString();
                            final physical =
                                cycle['physical_state']?.toString() ??
                                'unknown';
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  Icons.pedal_bike,
                                  color: status == 'available'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                title: Text(cycle['cycle_number'].toString()),
                                subtitle: Text(
                                  '$stand · $status · physical: $physical',
                                ),
                                isThreeLine: false,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'qr') _showQr(cycle);
                                    if (action == 'move') _move(cycle);
                                    if (action == 'remove') _remove(cycle);
                                    if (action == 'disable')
                                      _setStatus(cycle, 'disabled');
                                    if (action == 'verify')
                                      _verifyInventory(cycle);
                                    if (action == 'unassign')
                                      _clearStaleAssignment(cycle);
                                    if (action == 'rename') _renameCycle(cycle);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'qr',
                                      child: Text('Show QR'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'move',
                                      child: Text('Assign stand'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Edit cycle name'),
                                    ),
                                    if (cycle['stand_id'] != null &&
                                        status != 'in_use')
                                      const PopupMenuItem(
                                        value: 'verify',
                                        child: Text('Verify ESP inventory'),
                                      ),
                                    if (cycle['stand_id'] != null &&
                                        physical == 'absent' &&
                                        status != 'in_use')
                                      const PopupMenuItem(
                                        value: 'unassign',
                                        child: Text(
                                          'Clear stale stand assignment',
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove cycle'),
                                    ),
                                    if (status != 'disabled')
                                      const PopupMenuItem(
                                        value: 'disable',
                                        child: Text('Disable'),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
  );
}
