import 'package:flutter/material.dart';
import 'admin_users_tab.dart';
import 'admin_cycles_tab.dart';
import 'admin_stands_tab.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final List<Widget> _tabs = const [
    AdminUsersTab(),
    AdminCyclesTab(),
    AdminStandsTab(),
  ];
  final List<String> _titles = ['Users', 'Cycles', 'Stands'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        backgroundColor: Colors.green.shade700,
      ),
      body: _tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        selectedItemColor: Colors.green.shade700,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Users'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_bike), label: 'Cycles'),
          BottomNavigationBarItem(icon: Icon(Icons.storefront), label: 'Stands'),
        ],
      ),
    );
  }
}