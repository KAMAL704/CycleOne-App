import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  // ==================== FETCH USERS (WITH DEBUG) ====================
  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      print('🔄 Fetching users from profiles...');

      final response = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .order('updated_at', ascending: false);

      print('✅ Users fetched: ${response.length}');

      setState(() {
        _users = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });

      if (_users.isEmpty) {
        print('⚠️ No users found in profiles table!');
        setState(() {
          _errorMessage = 'No users found in profiles table. Please run SQL to populate profiles.';
        });
      }
    } catch (e) {
      print('❌ Error fetching users: $e');
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  // ==================== CREATE USER ====================
  Future<void> _createUser() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create User'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => v!.contains('@') ? null : 'Invalid email',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Temporary Password'),
                obscureText: true,
                validator: (v) => v!.length >= 6 ? null : 'Min 6 chars',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (shouldCreate != true) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final response = await Supabase.instance.client.functions.invoke(
      'invite-user',
      body: {'email': email, 'password': password},
    );
    if (mounted) Navigator.pop(context);
    if (response.status == 200) {
      _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User $email created. Password: $password')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${response.data['error']}')),
        );
      }
    }
  }

  // ==================== BLOCK / UNBLOCK ====================
  Future<void> _toggleBlock(String userId, bool currentBlocked) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final response = await Supabase.instance.client.functions.invoke(
      'toggle-block-user',
      body: {'userId': userId, 'isBlocked': !currentBlocked},
    );
    if (mounted) Navigator.pop(context);
    if (response.status == 200) {
      _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(!currentBlocked ? 'User blocked' : 'User unblocked')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.data['error']}')),
        );
      }
    }
  }

  // ==================== DELETE USER ====================
  Future<void> _deleteUser(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: const Text('Permanently delete this user?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final response = await Supabase.instance.client.functions.invoke(
      'delete-user',
      body: {'userId': userId},
    );
    if (mounted) Navigator.pop(context);
    if (response.status == 200) {
      _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User deleted')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.data['error']}')),
        );
      }
    }
  }

  // ==================== RESET PASSWORD ====================
  Future<void> _resetPassword(String userId, String email) async {
    final newPassword = 'Temp@${DateTime.now().millisecondsSinceEpoch % 10000}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reset password for $email?'),
            const SizedBox(height: 8),
            Text('New password: $newPassword', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirm != true) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final response = await Supabase.instance.client.functions.invoke(
      'reset-user-password',
      body: {'userId': userId, 'newPassword': newPassword},
    );
    if (mounted) Navigator.pop(context);
    if (response.status == 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset to: $newPassword')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.data['error']}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _createUser,
            tooltip: 'Create User',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchUsers,
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : _users.isEmpty
          ? const Center(child: Text('No users found.'))
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _users.length,
        itemBuilder: (context, i) {
          final user = _users[i];
          final isBlocked = user['is_blocked'] ?? false;
          final isAdmin = user['role'] == 'admin';

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: isBlocked ? Colors.red.shade100 : Colors.green.shade100,
                child: Icon(Icons.person, color: isBlocked ? Colors.red : Colors.green),
              ),
              title: Text(
                user['email'] ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text('ID: ${user['id'].substring(0, 8)}...'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isAdmin) const Chip(label: Text('Admin'), backgroundColor: Colors.green),
                  if (isBlocked) const Chip(label: Text('Blocked'), backgroundColor: Colors.red),
                ],
              ),
              children: [
                const Divider(),
                ListTile(
                  title: Text('Branch: ${user['branch'] ?? 'Not set'}'),
                  leading: const Icon(Icons.school, size: 20),
                ),
                ListTile(
                  title: Text('Year: ${user['year'] ?? 'Not set'}'),
                  leading: const Icon(Icons.calendar_today, size: 20),
                ),
                ListTile(
                  title: Text('Mobile: ${user['mobile'] ?? 'Not set'}'),
                  leading: const Icon(Icons.phone, size: 20),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // BLOCK / UNBLOCK
                      ElevatedButton.icon(
                        onPressed: () => _toggleBlock(user['id'], isBlocked),
                        icon: Icon(isBlocked ? Icons.check_circle : Icons.block, size: 18),
                        label: Text(isBlocked ? 'Unblock' : 'Block'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isBlocked ? Colors.green : Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      // RESET PASSWORD
                      ElevatedButton.icon(
                        onPressed: () => _resetPassword(user['id'], user['email']),
                        icon: const Icon(Icons.password, size: 18),
                        label: const Text('Reset Password'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      // DELETE
                      ElevatedButton.icon(
                        onPressed: () => _deleteUser(user['id']),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}