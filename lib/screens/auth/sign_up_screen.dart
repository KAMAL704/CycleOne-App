import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../providers/auth_provider.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _registration = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _registration, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthProvider>().signUp(
            name: _name.text,
            email: _email.text,
            password: _password.text,
            phone: _phone.text,
            registrationId: _registration.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created. Check your college email to verify it, then sign in.')));
        Navigator.pop(context);
      }
    } on AppException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(padding: const EdgeInsets.all(24), children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: _required),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'College email'), validator: _required),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: _required),
              TextFormField(controller: _registration, decoration: const InputDecoration(labelText: 'Registration ID'), validator: _required),
              TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (8+ characters)'), validator: (value) => (value ?? '').length >= 8 ? null : 'Use at least 8 characters'),
              TextFormField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password'), validator: (value) => value == _password.text ? null : 'Passwords do not match'),
              const SizedBox(height: 24),
              FilledButton(onPressed: _loading ? null : _submit, child: _loading ? const CircularProgressIndicator() : const Text('Create account')),
            ]),
          ),
        ),
      );

  String? _required(String? value) => (value ?? '').trim().isEmpty ? 'Required' : null;
}
