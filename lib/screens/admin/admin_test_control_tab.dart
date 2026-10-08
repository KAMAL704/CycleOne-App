import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminTestControlTab extends StatefulWidget {
  const AdminTestControlTab({super.key});

  @override
  State<AdminTestControlTab> createState() => _AdminTestControlTabState();
}

class _AdminTestControlTabState extends State<AdminTestControlTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _cycles = const [];
  List<Map<String, dynamic>> _assignments = const [];
  List<Map<String, dynamic>> _activeRides = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
            .from('profiles')
            .select('id, name, email, role, status')
            .order('name'),
        _client
            .from('cycles')
            .select('id, cycle_number, status, stand_id, physical_state'),
        _client
            .from('admin_test_cycle_assignments')
            .select('id, user_id, cycle_id, stand_id, phase, note, created_at')
            .eq('status', 'assigned')
            .order('created_at', ascending: false),
        _client
            .from('rides')
            .select('id, user_id, cycle_id, started_at')
            .eq('status', 'active'),
      ]);
      if (!mounted) return;
      setState(() {
        _users = List<Map<String, dynamic>>.from(results[0] as List);
        _cycles = List<Map<String, dynamic>>.from(results[1] as List);
        _assignments = List<Map<String, dynamic>>.from(results[2] as List);
        _activeRides = List<Map<String, dynamic>>.from(results[3] as List);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load test controls: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _assignmentFor(String userId) {
    for (final assignment in _assignments) {
      if (assignment['user_id']?.toString() == userId) return assignment;
    }
    return null;
  }

  Map<String, dynamic>? _rideFor(String userId) {
    for (final ride in _activeRides) {
      if (ride['user_id']?.toString() == userId) return ride;
    }
    return null;
  }

  Map<String, dynamic>? _cycleFor(String? cycleId) {
    if (cycleId == null) return null;
    for (final cycle in _cycles) {
      if (cycle['id']?.toString() == cycleId) return cycle;
    }
    return null;
  }

  String _userLabel(Map<String, dynamic> user) {
    final name = user['name']?.toString().trim() ?? '';
    final email = user['email']?.toString() ?? '';
    return name.isEmpty ? email : '$name · $email';
  }

  String _cycleLabel(Map<String, dynamic> cycle) {
    final number = cycle['cycle_number']?.toString() ?? 'Unknown cycle';
    final status = cycle['status']?.toString() ?? 'unknown';
    final physical = cycle['physical_state']?.toString() ?? 'unknown';
    return '$number · $status · physical $physical';
  }

  Future<void> _assignDialog({String? initialUserId}) async {
    if (_users.isEmpty || _cycles.isEmpty) {
      _message('Create at least one user and one cycle first.');
      return;
    }
    String? userId = initialUserId ?? _users.first['id']?.toString();
    String? cycleId = _cycles.first['id']?.toString();
    final note = TextEditingController(text: 'Test-only admin assignment');
    final formKey = GlobalKey<FormState>();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign test cycle'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: userId,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Colors.black87),
                    decoration: const InputDecoration(labelText: 'User'),
                    items: _users
                        .map(
                          (user) => DropdownMenuItem(
                            value: user['id'].toString(),
                            child: Text(
                              _userLabel(user),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => userId = value),
                    validator: (value) =>
                        value == null ? 'Choose a user' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: cycleId,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Colors.black87),
                    decoration: const InputDecoration(labelText: 'Cycle'),
                    items: _cycles
                        .map(
                          (cycle) => DropdownMenuItem(
                            value: cycle['id'].toString(),
                            child: Text(
                              _cycleLabel(cycle),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => cycleId = value),
                    validator: (value) =>
                        value == null ? 'Choose a cycle' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: note,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Test note (optional)',
                    ),
                  ),
                ],
              ),
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
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || userId == null || cycleId == null) {
      note.dispose();
      return;
    }
    try {
      await _client.rpc(
        'admin_test_assign_cycle',
        params: {
          'p_user_id': userId,
          'p_cycle_id': cycleId,
          'p_note': note.text.trim(),
        },
      );
      await _load();
      _message(
        'Test cycle assigned. User will see it on the Cycle page and can choose the ESP stand there. Database inventory and real rides are not changed.',
      );
    } catch (error) {
      _message('Could not assign test cycle: $error');
    } finally {
      note.dispose();
    }
  }

  Future<void> _unassign(String userId) async {
    try {
      await _client.rpc(
        'admin_test_unassign_cycle',
        params: {'p_user_id': userId},
      );
      await _load();
      _message(
        'Test cycle removed. Real ride and ESP inventory were not changed.',
      );
    } catch (error) {
      _message('Could not remove test cycle: $error');
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : () => _assignDialog(),
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Assign test cycle'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.science_outlined),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'TEST MODE\nThe assigned user sees this cycle on the main Cycle page. The user chooses the ESP stand for unlock and return; verified MAC communication is still required, while database inventory and real rides remain unchanged.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ..._users.map((user) {
                  final userId = user['id'].toString();
                  final assignment = _assignmentFor(userId);
                  final assignedCycle = _cycleFor(
                    assignment?['cycle_id']?.toString(),
                  );
                  final ride = _rideFor(userId);
                  final rideCycle = _cycleFor(ride?['cycle_id']?.toString());
                  final isBlocked = user['status'] != 'active';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _userLabel(user),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'assign')
                                    _assignDialog(initialUserId: userId);
                                  if (action == 'remove') _unassign(userId);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'assign',
                                    child: Text('Assign / replace test cycle'),
                                  ),
                                  if (assignment != null)
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove test cycle'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            '${user['role']} · ${isBlocked ? 'blocked' : 'active'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          if (assignment != null && assignedCycle != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.science),
                              title: Text(
                                'Test cycle: ${assignedCycle['cycle_number']}',
                              ),
                              subtitle: Text(
                                'Phase: ${assignment['phase'] ?? 'assigned'} · ESP is chosen by the user\nDatabase status: ${assignedCycle['status']} · physical: ${assignedCycle['physical_state'] ?? 'unknown'}',
                              ),
                            )
                          else
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(Icons.remove_circle_outline),
                              title: Text('No test cycle assigned'),
                            ),
                          if (ride != null && rideCycle != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.directions_bike),
                              title: Text(
                                'Real active ride: ${rideCycle['cycle_number']}',
                              ),
                              subtitle: const Text(
                                'This is separate from the test assignment.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
  );
}
