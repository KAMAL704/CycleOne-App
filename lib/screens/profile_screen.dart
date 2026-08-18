import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cycle_provider.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isRefreshed = false;

  @override
  void initState() {
    super.initState();
    // ✅ Only refresh once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRefreshed) {
        _isRefreshed = true;
        context.read<CycleProvider>().refreshCycle();
      }
    });
  }

  // ✅ Remove didChangeDependencies - it was causing extra refreshes

  @override
  Widget build(BuildContext context) {
    final cycleProvider = context.watch<CycleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.green.shade700,
      ),
      body: cycleProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.green,
              child: Icon(Icons.person, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Consumer<AuthProvider>(
                  builder: (context, authProvider, _) {
                    final profile = authProvider.profile;
                    return Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.email),
                          title: const Text('Email'),
                          subtitle: Text(authProvider.userEmail ?? 'Not signed in'),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.school),
                          title: const Text('Branch/RegNo.'),
                          subtitle: Text(profile['branch']?.isNotEmpty == true ? profile['branch'] : 'Not Available'),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.date_range),
                          title: const Text('Year'),
                          subtitle: Text(profile['year']?.isNotEmpty == true ? profile['year'] : 'Not Available'),
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.phone),
                          title: const Text('Mobile Number'),
                          subtitle: Text(profile['mobile']?.isNotEmpty == true ? profile['mobile'] : 'Not Available'),
                        ),
                        const Divider(),
                        Consumer<CycleProvider>(
                          builder: (context, cycleProvider, _) => ListTile(
                            leading: const Icon(Icons.cable),
                            title: const Text('Current Cycle'),
                            subtitle: Text(
                              cycleProvider.hasCycle
                                  ? cycleProvider.currentCycleId!
                                  : 'No cycle allocated',
                              style: TextStyle(
                                fontWeight: cycleProvider.hasCycle ? FontWeight.bold : FontWeight.normal,
                                color: cycleProvider.hasCycle ? Colors.green : Colors.grey,
                              ),
                            ),
                            trailing: cycleProvider.hasCycle
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: Colors.red),
                foregroundColor: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await context.read<AuthProvider>().signOut(context);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}