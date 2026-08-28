import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  PermissionStatus _locationStatus = PermissionStatus.denied;
  PermissionStatus _wifiStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await Permission.location.status;
    PermissionStatus wifi = PermissionStatus.denied;
    try { wifi = await Permission.nearbyWifiDevices.status; } on UnsupportedError { wifi = PermissionStatus.granted; }
    if (mounted) setState(() { _locationStatus = status; _wifiStatus = wifi; });
  }

  Future<void> _requestPermission() async {
    final status = await Permission.location.request();
    PermissionStatus wifi = _wifiStatus;
    try { wifi = await Permission.nearbyWifiDevices.request(); } on UnsupportedError { wifi = PermissionStatus.granted; }
    if (mounted) setState(() { _locationStatus = status; _wifiStatus = wifi; });
    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission granted!')),
      );
    } else if (status.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission denied. Some features may not work.')),
      );
    } else if (status.isPermanentlyDenied) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('Please enable location from app settings.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location Permissions')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Hello !!!',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
            const Center(child: Text('Your last session', style: TextStyle(fontSize: 18))),
            const SizedBox(height: 32),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.location_on, size: 48, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'Location and nearby Wi-Fi permissions are required for maps and stand locks.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const Text('Please grant the permissions', style: TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Location is used to find stands. Nearby Wi-Fi is used to reach the selected lock.')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _requestPermission,
                      icon: const Icon(Icons.gps_fixed),
                      label: const Text('Request permissions'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _locationStatus.isGranted ? Colors.green.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Location:'),
                          Chip(
                            label: Text(_locationStatus.isGranted ? 'Granted' : 'Not Granted'),
                            backgroundColor: _locationStatus.isGranted ? Colors.green : Colors.orange.shade100,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Nearby Wi-Fi:'),
                      Chip(label: Text(_wifiStatus.isGranted ? 'Granted' : 'Not granted'), backgroundColor: _wifiStatus.isGranted ? Colors.green : Colors.orange.shade100),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
