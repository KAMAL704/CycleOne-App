import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_exception.dart';
import '../core/logging/app_logger.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({SupabaseClient? client}) : _client = client ?? Supabase.instance.client {
    _subscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.session == null) {
        _profile = null;
        _isAdmin = false;
        notifyListeners();
      } else {
        unawaited(loadProfile());
      }
    });
    if (isSignedIn) unawaited(loadProfile());
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _subscription;
  Map<String, dynamic>? _profile;
  bool _isAdmin = false;
  bool _loadingProfile = false;

  bool get isSignedIn => _client.auth.currentSession != null;
  User? get currentUser => _client.auth.currentUser;
  String? get userEmail => currentUser?.email;
  Map<String, dynamic> get profile => _profile ?? const {};
  bool get isAdmin => _isAdmin;
  bool get isLoadingProfile => _loadingProfile;

  Future<void> loadProfile() async {
    final user = currentUser;
    if (user == null) return;
    _loadingProfile = true;
    notifyListeners();
    try {
      final row = await _client.from('profiles').select('*').eq('id', user.id).maybeSingle();
      _profile = row == null ? null : Map<String, dynamic>.from(row);
      _isAdmin = _profile?['role'] == 'admin' && _profile?['status'] == 'active';
    } catch (error, stackTrace) {
      AppLogger.error('AUTH', error, stackTrace);
    } finally {
      _loadingProfile = false;
      notifyListeners();
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String registrationId,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (name.trim().isEmpty || phone.trim().isEmpty || registrationId.trim().isEmpty) {
      throw const AppException('Name, phone number, and registration ID are required.');
    }
    if (!AppConfig.isCollegeEmail(normalized)) {
      throw AppException('Use your @${AppConfig.collegeEmailDomain} college email address.');
    }
    if (password.length < 8) throw const AppException('Use a password with at least 8 characters.');
    try {
      await _client.auth.signUp(
        email: normalized,
        password: password,
        data: {'name': name.trim(), 'phone': phone.trim(), 'registration_id': registrationId.trim()},
        emailRedirectTo: null,
      );
    } on AuthException catch (error) {
      throw AppException(error.message);
    } catch (error, stackTrace) {
      AppLogger.error('AUTH', error, stackTrace);
      throw const AppException('We could not create your account. Check your connection and try again.');
    }
  }

  Future<void> signIn(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    if (!AppConfig.isCollegeEmail(normalized)) {
      throw AppException('Use your @${AppConfig.collegeEmailDomain} college email address.');
    }
    try {
      await _client.auth.signInWithPassword(email: normalized, password: password);
      await loadProfile();
      if (_profile?['status'] != 'active') {
        await _client.auth.signOut();
        throw const AppException('This account is disabled. Please contact CycleOne support.');
      }
    } on AuthException catch (error) {
      final message = error.message.toLowerCase().contains('email not confirmed')
          ? 'Please verify your college email before signing in.'
          : error.message;
      throw AppException(message);
    } catch (error, stackTrace) {
      AppLogger.error('AUTH', error, stackTrace);
      throw const AppException('We could not sign you in. Check your connection and try again.');
    }
  }

  Future<void> updateProfile({required String name, required String phone, required String registrationId}) async {
    if (!isSignedIn) throw const AppException('Please sign in again.');
    if (name.trim().isEmpty || phone.trim().isEmpty || registrationId.trim().isEmpty) {
      throw const AppException('Name, phone number, and registration ID are required.');
    }
    try {
      await _client.from('profiles').update({
        'name': name.trim(),
        'phone': phone.trim(),
        'registration_id': registrationId.trim(),
      }).eq('id', currentUser!.id);
      await loadProfile();
    } on PostgrestException catch (error) {
      throw AppException(error.message);
    } catch (error, stackTrace) {
      AppLogger.error('AUTH', error, stackTrace);
      throw const AppException('We could not save your profile. Check your connection and try again.');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _profile = null;
    _isAdmin = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
