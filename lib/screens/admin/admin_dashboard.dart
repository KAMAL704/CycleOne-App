import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_cycles_tab.dart';
import 'admin_stands_tab.dart';
import 'admin_users_tab.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final _tabs = const [AdminOverviewTab(), AdminUsersTab(), AdminCyclesTab(), AdminStandsTab()];
  final _titles = const ['Admin overview', 'Users', 'Cycles', 'Stands'];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_titles[_selectedIndex])),
        body: _tabs[_selectedIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Users'),
            NavigationDestination(icon: Icon(Icons.pedal_bike_outlined), selectedIcon: Icon(Icons.pedal_bike), label: 'Cycles'),
            NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Stands'),
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
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _client.from('cycles').select('status, physical_state'),
        _client.from('rides').select('status'),
        _client.from('stands').select('status'),
      ]);
      final cycles = List<Map<String, dynamic>>.from(results[0] as List);
      final rides = List<Map<String, dynamic>>.from(results[1] as List);
      final stands = List<Map<String, dynamic>>.from(results[2] as List);
      if (mounted) setState(() => _counts = {
            'cycles': cycles.length,
            'available': cycles.where((row) => row['status'] == 'available' && row['physical_state'] == 'present').length,
            'activeRides': rides.where((row) => row['status'] == 'active').length,
            'completedRides': rides.where((row) => row['status'] == 'completed').length,
            'stands': stands.length,
            'activeStands': stands.where((row) => row['status'] == 'active').length,
          });
    } catch (error) { if (mounted) setState(() => _error = 'Could not load dashboard: $error'); }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Retry'))]));
    if (counts == null) return const Center(child: CircularProgressIndicator());
    final cards = [
      ('Total cycles', counts['cycles']!, Icons.pedal_bike),
      ('Available', counts['available']!, Icons.check_circle_outline),
      ('Active rides', counts['activeRides']!, Icons.route),
      ('Completed rides', counts['completedRides']!, Icons.history),
      ('Total stands', counts['stands']!, Icons.storefront),
      ('Active stands', counts['activeStands']!, Icons.wifi),
    ];
    return RefreshIndicator(onRefresh: _load, child: GridView.builder(padding: const EdgeInsets.all(16), itemCount: cards.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.35), itemBuilder: (_, index) {
      final card = cards[index];
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(card.$3, color: Theme.of(context).colorScheme.primary), Text(card.$1), Text(card.$2.toString(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))])));
    }));
  }
}
