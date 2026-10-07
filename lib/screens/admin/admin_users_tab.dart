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
      final rows = await _client
          .from('profiles')
          .select(
            'id, name, email, phone, registration_id, role, status, created_at, updated_at',
          )
          .order('updated_at', ascending: false);
      if (mounted) {
        setState(() => _users = List<Map<String, dynamic>>.from(rows));
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load users: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _callAdminFunction(
    String name,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.functions.invoke(name, body: body);
    if (response.status < 200 || response.status >= 300) {
      throw Exception(response.data?.toString() ?? 'Request failed');
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> user) async {
    if (user['id'] == _client.auth.currentUser?.id) {
      _message('You cannot disable your own admin account.');
      return;
    }
    final next = user['status'] == 'active' ? 'disabled' : 'active';
    try {
      await _client.rpc(
        'admin_set_user_status',
        params: {'p_user_id': user['id'], 'p_status': next},
      );
      await _load();
    } catch (error) {
      _message('Could not update user access: $error');
    }
  }

  Future<void> _setRole(Map<String, dynamic> user, String role) async {
    if (user['id'] == _client.auth.currentUser?.id && role != 'admin') {
      _message('You cannot remove your own administrator role.');
      return;
    }
    try {
      await _client
          .from('profiles')
          .update({'role': role})
          .eq('id', user['id']);
      await _load();
    } catch (error) {
      _message('Could not update role: $error');
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reset password · ${user['email'] ?? ''}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (value) => value == null || value.length < 8
                    ? 'Use at least 8 characters'
                    : null,
              ),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (value) =>
                    value != password.text ? 'Passwords do not match' : null,
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
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (submitted != true) {
      password.dispose();
      confirm.dispose();
      return;
    }
    try {
      await _callAdminFunction('reset-user-password', {
        'userId': user['id'],
        'newPassword': password.text,
      });
      _message('Password reset successfully.');
    } catch (error) {
      _message('Could not reset password: $error');
    } finally {
      password.dispose();
      confirm.dispose();
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (user['id'] == _client.auth.currentUser?.id) {
      _message('You cannot delete your own admin account.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text(
          'Delete ${user['email'] ?? 'this user'} permanently from authentication and profiles?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _callAdminFunction('delete-user', {'userId': user['id']});
      await _load();
      _message('User deleted.');
    } catch (error) {
      _message('Could not delete user: $error');
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
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final user = _users[index];
                final active = user['status'] == 'active';
                final isSelf = user['id'] == _client.auth.currentUser?.id;
                final name = user['name']?.toString().trim() ?? '';
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                      ),
                    ),
                    title: Text(
                      name.isNotEmpty ? name : user['email'].toString(),
                    ),
                    subtitle: Text(
                      '${user['email']}\n${user['registration_id'] ?? 'No registration ID'} · ${user['role']} · ${user['status']}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'status') _toggleStatus(user);
                        if (action == 'admin') _setRole(user, 'admin');
                        if (action == 'student') _setRole(user, 'student');
                        if (action == 'password') _resetPassword(user);
                        if (action == 'delete') _deleteUser(user);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'status',
                          enabled: !isSelf,
                          child: Text(active ? 'Block user' : 'Unblock user'),
                        ),
                        const PopupMenuItem(
                          value: 'password',
                          child: Text('Reset password'),
                        ),
                        if (user['role'] == 'admin')
                          const PopupMenuItem(
                            value: 'student',
                            child: Text('Make student'),
                          )
                        else
                          const PopupMenuItem(
                            value: 'admin',
                            child: Text('Make admin'),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          enabled: !isSelf,
                          child: const Text('Delete user'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
  );
}
