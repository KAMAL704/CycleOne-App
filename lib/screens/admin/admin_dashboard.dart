import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_cycles_tab.dart';
import 'admin_stands_tab.dart';
import 'admin_test_control_tab.dart';
import 'admin_users_tab.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final _tabs = const [
    AdminOverviewTab(),
    AdminUsersTab(),
    AdminCyclesTab(),
    AdminStandsTab(),
    AdminTestControlTab(),
  ];
  final _titles = const [
    'Admin overview',
    'Users',
    'Cycles',
    'Stands',
    'Test control',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_titles[_selectedIndex])),
    body: _tabs[_selectedIndex],
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Overview',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Users',
        ),
        NavigationDestination(
          icon: Icon(Icons.pedal_bike_outlined),
          selectedIcon: Icon(Icons.pedal_bike),
          label: 'Cycles',
        ),
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront),
          label: 'Stands',
        ),
        NavigationDestination(
          icon: Icon(Icons.science_outlined),
          selectedIcon: Icon(Icons.science),
          label: 'Test control',
        ),
      ],
    ),
  );
}

class AdminOverviewTab extends StatefulWidget {
  const AdminOverviewTab({super.key});

  @override
  State<AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<AdminOverviewTab> {
  final _client = Supabase.instance.client;
  Map<String, int>? _counts;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _cycles = const [];
  List<Map<String, dynamic>> _rides = const [];
  List<Map<String, dynamic>> _stands = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _client.from('profiles').select('id, name, email, role, status'),
        _client
            .from('cycles')
            .select('id, cycle_number, status, physical_state, stand_id'),
        _client
            .from('rides')
            .select('id, user_id, cycle_id, status, started_at'),
        _client.from('stands').select('id, name, status'),
      ]);
      final users = List<Map<String, dynamic>>.from(results[0] as List);
      final cycles = List<Map<String, dynamic>>.from(results[1] as List);
      final rides = List<Map<String, dynamic>>.from(results[2] as List);
      final stands = List<Map<String, dynamic>>.from(results[3] as List);
      if (mounted)
        setState(() {
          _users = users;
          _cycles = cycles;
          _rides = rides;
          _stands = stands;
          _counts = {
            'users': users.length,
            'blockedUsers': users
                .where((row) => row['status'] == 'disabled')
                .length,
            'cycles': cycles.length,
            'available': cycles
                .where(
                  (row) =>
                      row['status'] == 'available' &&
                      row['physical_state'] == 'present',
                )
                .length,
            'activeRides': rides
                .where((row) => row['status'] == 'active')
                .length,
            'completedRides': rides
                .where((row) => row['status'] == 'completed')
                .length,
            'stands': stands.length,
            'activeStands': stands
                .where((row) => row['status'] == 'active')
                .length,
          };
        });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load dashboard: $error');
    }
  }

  Future<void> _showDetails(String key) async {
    final rows = switch (key) {
      'users' => _users,
      'blockedUsers' =>
        _users.where((row) => row['status'] == 'disabled').toList(),
      'cycles' => _cycles,
      'available' =>
        _cycles
            .where(
              (row) =>
                  row['status'] == 'available' &&
                  row['physical_state'] == 'present',
            )
            .toList(),
      'activeRides' =>
        _rides.where((row) => row['status'] == 'active').toList(),
      'completedRides' =>
        _rides.where((row) => row['status'] == 'completed').toList(),
      'stands' => _stands,
      'activeStands' =>
        _stands.where((row) => row['status'] == 'active').toList(),
      _ => const <Map<String, dynamic>>[],
    };
    final title = switch (key) {
      'users' => 'All users',
      'blockedUsers' => 'Blocked users',
      'cycles' => 'All cycles',
      'available' => 'Available cycles',
      'activeRides' => 'Active rides',
      'completedRides' => 'Completed rides',
      'stands' => 'All stands',
      'activeStands' => 'Active stands',
      _ => 'Details',
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        content: SizedBox(
          width: 440,
          height: MediaQuery.sizeOf(context).height * .52,
          child: rows.isEmpty
              ? const Center(child: Text('No records found.'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => _detailTile(key, rows[index]),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailTile(String key, Map<String, dynamic> row) {
    if (key == 'users' || key == 'blockedUsers') {
      final name = row['name']?.toString().trim();
      return ListTile(
        leading: CircleAvatar(
          child: Text(name?.isNotEmpty == true ? name![0].toUpperCase() : '?'),
        ),
        title: Text(name?.isNotEmpty == true ? name! : row['email'].toString()),
        subtitle: Text('${row['email']} · ${row['role']} · ${row['status']}'),
      );
    }
    if (key == 'stands' || key == 'activeStands') {
      return ListTile(
        leading: Icon(
          Icons.storefront,
          color: row['status'] == 'active' ? Colors.green : Colors.grey,
        ),
        title: Text(row['name']?.toString() ?? 'Unnamed stand'),
        subtitle: Text(row['status']?.toString() ?? 'unknown'),
      );
    }
    if (key == 'activeRides' || key == 'completedRides') {
      final user = _findById(_users, row['user_id']);
      final cycle = _findById(_cycles, row['cycle_id']);
      final userName = user?['name']?.toString().trim();
      return ListTile(
        leading: Icon(
          key == 'activeRides' ? Icons.directions_bike : Icons.check_circle,
          color: key == 'activeRides' ? Colors.orange : Colors.green,
        ),
        title: Text(
          'Cycle ${cycle?['cycle_number'] ?? row['cycle_id'] ?? 'Unknown'}',
        ),
        subtitle: Text(
          '${userName?.isNotEmpty == true ? userName : user?['email'] ?? 'Unknown user'} · ${row['status']}\n${_formatDate(row['started_at'])}',
        ),
        isThreeLine: true,
      );
    }
    final stand = _findById(_stands, row['stand_id']);
    return ListTile(
      leading: Icon(
        Icons.pedal_bike,
        color: row['status'] == 'available' ? Colors.green : Colors.orange,
      ),
      title: Text(row['cycle_number']?.toString() ?? 'Unnamed cycle'),
      subtitle: Text(
        '${row['status']} · physical ${row['physical_state'] ?? 'unknown'}\n${stand?['name'] ?? 'Unassigned'}',
      ),
      isThreeLine: true,
    );
  }

  Map<String, dynamic>? _findById(List<Map<String, dynamic>> rows, Object? id) {
    if (id == null) return null;
    for (final row in rows) {
      if (row['id']?.toString() == id.toString()) return row;
    }
    return null;
  }

  String _formatDate(Object? value) {
    if (value == null) return 'Unknown time';
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toLocal().toString().split('.').first ?? value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    if (_error != null)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    if (counts == null) return const Center(child: CircularProgressIndicator());
    final cards = [
      ('Total users', 'users', counts['users']!, Icons.people),
      (
        'Blocked users',
        'blockedUsers',
        counts['blockedUsers']!,
        Icons.person_off,
      ),
      ('Total cycles', 'cycles', counts['cycles']!, Icons.pedal_bike),
      (
        'Available',
        'available',
        counts['available']!,
        Icons.check_circle_outline,
      ),
      ('Active rides', 'activeRides', counts['activeRides']!, Icons.route),
      (
        'Completed rides',
        'completedRides',
        counts['completedRides']!,
        Icons.history,
      ),
      ('Total stands', 'stands', counts['stands']!, Icons.storefront),
      ('Active stands', 'activeStands', counts['activeStands']!, Icons.wifi),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: cards.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
        ),
        itemBuilder: (_, index) {
          final card = cards[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showDetails(card.$2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(card.$4, color: Theme.of(context).colorScheme.primary),
                    Text(card.$1),
                    Text(
                      card.$3.toString(),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
