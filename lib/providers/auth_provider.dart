import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cycle_provider.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool get isSignedIn => _supabase.auth.currentSession != null;
  User? get currentUser => _supabase.auth.currentUser;
  String? get userEmail => _supabase.auth.currentUser?.email;

  Map<String, dynamic>? _profile;
  Map<String, dynamic> get profile => _profile ?? {};
  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  Future<void> _loadProfile() async {
    if (!isSignedIn) return;
    final userId = currentUser!.id;
    final response = await _supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();
    _profile = response;
    _isAdmin = _profile?['role'] == 'admin';
    notifyListeners();
  }

  // ✅ Added signUp method
  Future<void> signUp(String email, String password, BuildContext context) async {
    try {
      final response = await _supabase.auth.signUp(email: email, password: password);
      if (response.user != null) {
        await _supabase.from('profiles').upsert({
          'id': response.user!.id,
          'email': email,
          'role': 'user',
          'name': email.split('@').first,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign up successful! Please sign in.')),
          );
          Navigator.pop(context);
        }
      }
    } on AuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> updateProfile({
    String? branch,
    String? year,
    String? mobile,
  }) async {
    if (!isSignedIn) return;
    final userId = currentUser!.id;
    final updates = {
      'id': userId,
      'email': userEmail,
      if (branch != null) 'branch': branch,
      if (year != null) 'year': year,
      if (mobile != null) 'mobile': mobile,
    };
    await _supabase.from('profiles').upsert(updates);
    await _loadProfile();
    notifyListeners();
  }

  Future<void> signIn(String email, String password, BuildContext context) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        await _loadProfile();
        context.read<CycleProvider>().refreshCycle();
        notifyListeners();
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in failed. Check credentials.')),
          );
        }
      }
    } on AuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> signOut(BuildContext context) async {
    await _supabase.auth.signOut();
    _profile = null;
    _isAdmin = false;
    context.read<CycleProvider>().reset();
    notifyListeners();
  }

  Future<void> updatePassword(String newPassword, BuildContext context) async {
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated. Please sign in again.')),
        );
        await signOut(context);
      }
    } on AuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}