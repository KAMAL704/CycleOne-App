import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/cycle_provider.dart';
import '../services/cycle_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cycle = context.watch<CycleProvider>();
    final profile = auth.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        CircleAvatar(radius: 42, child: Text((profile['name']?.toString().isNotEmpty ?? false) ? profile['name'].toString()[0].toUpperCase() : '?', style: const TextStyle(fontSize: 28))),
        const SizedBox(height: 20),
        _row(Icons.person_outline, 'Name', profile['name']?.toString() ?? '—'),
        _row(Icons.email_outlined, 'College email', auth.userEmail ?? '—'),
        _row(Icons.phone_outlined, 'Phone', profile['phone']?.toString() ?? '—'),
        _row(Icons.badge_outlined, 'Registration ID', profile['registration_id']?.toString() ?? '—'),
        _row(Icons.verified_user_outlined, 'Account status', profile['status']?.toString() ?? '—'),
        _row(Icons.pedal_bike, 'Current ride', cycle.hasCycle ? 'Cycle ${cycle.currentCycleId}' : 'No active ride'),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: CycleService().getRideHistory(),
          builder: (context, snapshot) => _row(Icons.route, 'Ride count', snapshot.hasData ? snapshot.data!.length.toString() : 'Loading…'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())), icon: const Icon(Icons.edit), label: const Text('Edit profile')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await context.read<AuthProvider>().signOut();
            context.read<CycleProvider>().reset();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) => Card(
        child: ListTile(leading: Icon(icon), title: Text(label), subtitle: Text(value)),
      );
}
