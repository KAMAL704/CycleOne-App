import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  // Simulate a re-check delay
  bool _isChecking = false;

  Future<void> _checkAgain() async {
    setState(() => _isChecking = true);
    // Simulate network call to check maintenance status
    await Future.delayed(const Duration(seconds: 2));
    // For demo, we always return to splash (you would check a real flag)
    if (mounted) {
      setState(() => _isChecking = false);
      // Navigate back to splash – if maintenance is over, the app will proceed.
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  void _launchSupportEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'kamalbajiya15@gmail.com',
      query: 'subject=TechFest%20App%20Support',
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email client.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated icon
              Icon(
                Icons.build_circle_outlined,
                size: 120,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 32),
              const Text(
                'App Update in Progress',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                "We're improving the CycleOne app.\nPlease try again after some time.",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Estimated completion time (optional)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  '⏳ Expected to be back online in ~30 minutes',
                  style: TextStyle(fontSize: 14, color: Colors.green),
                ),
              ),
              const SizedBox(height: 40),
              // Re‑check button with loading state
              _isChecking
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                onPressed: _checkAgain,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 50),
                ),
              ),
              const SizedBox(height: 16),
              // Contact support
              TextButton.icon(
                onPressed: _launchSupportEmail,
                icon: const Icon(Icons.email, size: 20),
                label: const Text('Contact Support'),
                style: TextButton.styleFrom(foregroundColor: Colors.blue),
              ),
              const SizedBox(height: 8),
              // App version info (optional)
              const Text(
                'Version 2.0.1',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}