import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final rows = await _client.from('profiles').select('id, name, email, phone, registration_id, role, status, created_at, updated_at').order('updated_at', ascending: false);
      if (mounted) setState(() => _users = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load users: $error');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    if (user['id'] == _client.auth.currentUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot disable your own admin account.')));
      return;
    }
    final next = user['status'] == 'active' ? 'disabled' : 'active';
    try { await _client.from('profiles').update({'status': next}).eq('id', user['id']); await _load(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update user: $error'))); }
  }

  Future<void> _setRole(Map<String, dynamic> user, String role) async {
    if (user['id'] == _client.auth.currentUser?.id && role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot remove your own administrator role.')));
      return;
    }
    try {
      await _client.from('profiles').update({'role': role}).eq('id', user['id']);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update role: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : RefreshIndicator(onRefresh: _load, child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final active = user['status'] == 'active';
                      return Card(child: ListTile(
                        leading: CircleAvatar(child: Text((user['name']?.toString().isNotEmpty ?? false) ? user['name'].toString()[0].toUpperCase() : '?')),
                        title: Text(user['name']?.toString().isNotEmpty == true ? user['name'].toString() : user['email'].toString()),
                        subtitle: Text('${user['email']}\n${user['registration_id'] ?? 'No registration ID'} · ${user['role']} · ${user['status']}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(onSelected: (action) {
                          if (action == 'status') _toggleStatus(user);
                          if (action == 'admin') _setRole(user, 'admin');
                          if (action == 'student') _setRole(user, 'student');
                        }, itemBuilder: (_) => [
                          PopupMenuItem(value: 'status', child: Text(active ? 'Disable user' : 'Enable user')),
                          if (user['role'] == 'admin') const PopupMenuItem(value: 'student', child: Text('Make student')) else const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                        ]),
                      ));
                    },
                  )),
      );
}
