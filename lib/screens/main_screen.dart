import 'package:cycle_one/screens/ride_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cycle_provider.dart';
import 'cycle_screen.dart';
import 'profile_screen.dart';
import 'feedback_screen.dart';
import 'permissions_screen.dart';
import 'admin/admin_dashboard.dart';
import 'map_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // ✅ Only refresh once on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isInitialized) {
        _isInitialized = true;
        context.read<CycleProvider>().refreshCycle();
      }
    });
  }

  List<Widget> get _screens {
    final isAdmin = context.watch<AuthProvider>().isAdmin;
    final screens = <Widget>[
      const CycleScreen(),
      const MapScreen(),
      const ProfileScreen(),
      const FeedbackScreen(),
      const PermissionsScreen(),
      const RideHistoryScreen(),
    ];
    if (isAdmin) {
      screens.insert(3, const AdminDashboard());
    }
    return screens;
  }

  List<BottomNavigationBarItem> get _navItems {
    final isAdmin = context.watch<AuthProvider>().isAdmin;
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.directions_bike),
        label: 'Cycle',
      ),
      const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
      const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      // const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
      const BottomNavigationBarItem(
        icon: Icon(Icons.feedback),
        label: 'Feedback',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.location_on),
        label: 'Permissions',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.history),
        label: 'History',
      ),
    ];
    if (isAdmin) {
      items.insert(
        3,
        const BottomNavigationBarItem(
          icon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final screens = _screens;
    final navItems = _navItems;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Do you want to exit CycleOne App?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: screens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
            // ✅ Only refresh when switching TO cycle tab (index 0)
            // and only if not already refreshing
            if (index == 0) {
              final provider = context.read<CycleProvider>();
              if (!provider.isLoading) {
                provider.refreshCycle();
              }
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white.withAlpha(225),
          selectedItemColor: Colors.green,
          unselectedItemColor: Colors.grey,
          items: navItems,
        ),
      ),
    );
  }
}
