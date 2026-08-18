import 'package:cycle_one/screens/maintenace_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/cycle_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/main_screen.dart';
import 'screens/splash_screen.dart';  // import new splash screen


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://lqzazbejzpxjndoegoly.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxxemF6YmVqenB4am5kb2Vnb2x5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2Mzc1MzUsImV4cCI6MjA5NTIxMzUzNX0.ytHROXhLa972Ay1NLRE_N2KcGvP8a5cOLUkBkfhn8Vo',
  );
  runApp(const CycleOneApp());
}

class CycleOneApp extends StatelessWidget {
  const CycleOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CycleProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: 'CycleOne',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(primarySwatch: Colors.green),
        initialRoute: '/splash',
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/home': (context) => const AuthWrapper(),
          '/maintenance': (context) => const MaintenanceScreen(),

        },

      ),
    );
  }
}

// AuthWrapper same as before (returns SignInScreen or MainScreen)
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    return authProvider.isSignedIn ? const MainScreen() : const SignInScreen();
  }
}