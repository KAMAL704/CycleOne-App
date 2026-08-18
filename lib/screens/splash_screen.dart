import 'package:flutter/material.dart';
import '../services/settings_service.dart'; // we'll create this

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Show splash for 2 seconds, then check maintenance
    Future.delayed(const Duration(seconds: 2), () {
      _checkMaintenance();
    });
  }

  Future<void> _checkMaintenance() async {
    final bool isUnderMaintenance = await SettingsService.isMaintenanceMode();
    if (mounted) {
      if (isUnderMaintenance) {
        Navigator.pushReplacementNamed(context, '/maintenance');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'CYCLEONE',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  letterSpacing: 2,
                ),
              ),
              const Text(
                'Connect - Commute - Conserve',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 40),
              const Text(
                'CycleOne',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.network(
                    'https://upload.wikimedia.org/wikipedia/en/4/4f/NHPC_logo.png', // fixed URL
                    height: 50,
                    errorBuilder: (_, __, ___) => const Text('NHPC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Sponsored by NHPC',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'SLIET',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Thanking Dr. Amit Kansal',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}