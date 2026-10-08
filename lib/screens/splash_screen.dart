import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Give the splash artwork time to render, then check release state.
    Future.delayed(const Duration(seconds: 2), () {
      _checkMaintenance();
    });
  }

  Future<void> _checkMaintenance() async {
    final update = await SettingsService.checkForUpdate();
    final bool isUnderMaintenance = await SettingsService.isMaintenanceMode();
    if (mounted) {
      if (update != null && update.mandatory) {
        Navigator.pushReplacementNamed(
          context,
          '/update',
          arguments: update,
        );
      } else if (isUnderMaintenance) {
        Navigator.pushReplacementNamed(context, '/maintenance');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  Image.asset(
                    'assets/images/splash_logo.png',
                    height: 50,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.pedal_bike, size: 50),
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
                'Thanking Dr. Manoj Sir(Faculty Advisor)',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
