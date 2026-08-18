import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/stand_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<Map<String, dynamic>> _stands = [];
  LatLng? _userLocation;
  bool _isLoading = true;
  bool _locationPermissionDenied = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadStands();
  }

  Future<void> _loadStands() async {
    setState(() => _isLoading = true);
    try {
      _stands = await StandService.getStands();
      await _getUserLocation();
    } catch (e) {
      print('Error loading stands: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationPermissionDenied = true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationPermissionDenied = true);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationPermissionDenied = true);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });

      // ✅ Wait for map to be built before moving
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_userLocation != null) {
          _mapController.move(_userLocation!, 15);
        }
      });
    } catch (e) {
      print('Error getting location: $e');
      setState(() => _locationPermissionDenied = true);
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371;
    double dLat = _toRadians(lat1 - lat2);
    double dLng = _toRadians(lng1 - lng2);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat2)) * cos(_toRadians(lat1)) *
            sin(dLng / 2) * sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * pi / 180;

  String _formatDistance(double distanceKm) {
    if (distanceKm < 1.0) {
      final meters = (distanceKm * 1000).round();
      return '$meters m';
    } else {
      return '${distanceKm.toStringAsFixed(1)} km';
    }
  }

  List<Map<String, dynamic>> _getNearestStands() {
    if (_userLocation == null) return _stands;
    return List.from(_stands)
      ..sort((a, b) {
        final distA = _calculateDistance(
          a['latitude']?.toDouble() ?? 0,
          a['longitude']?.toDouble() ?? 0,
          _userLocation!.latitude,
          _userLocation!.longitude,
        );
        final distB = _calculateDistance(
          b['latitude']?.toDouble() ?? 0,
          b['longitude']?.toDouble() ?? 0,
          _userLocation!.latitude,
          _userLocation!.longitude,
        );
        return distA.compareTo(distB);
      });
  }

  void _showStandDetails(Map<String, dynamic> stand, double distance) {
    final cycles = stand['cycles'] as List? ?? [];
    final available = cycles.where((c) => c['status'] == 'available').length;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.electric_bike, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stand['name'] ?? 'Unknown Stand',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.directions_bike),
              title: const Text('Available Cycles'),
              trailing: Text('$available / ${cycles.length}'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Distance from you'),
              trailing: Text(_formatDistance(distance)),
            ),
            if (available > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Unlock Cycle Here'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_locationPermissionDenied) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Location Required'),
          backgroundColor: Colors.green.shade700,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Location permission is required to find nearby stands.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'Please enable location in settings.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _getUserLocation,
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    final nearestStands = _getNearestStands();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Cycle Stands'),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getUserLocation,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStands,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _userLocation ?? const LatLng(30.1756, 76.7894),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.cycleone',
                ),
                if (_userLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 40,
                        height: 40,
                        point: _userLocation!,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: _stands.map((stand) {
                    final cycles = stand['cycles'] as List? ?? [];
                    final available = cycles.where((c) => c['status'] == 'available').length;
                    final distance = _userLocation != null
                        ? _calculateDistance(
                      stand['latitude']?.toDouble() ?? 0,
                      stand['longitude']?.toDouble() ?? 0,
                      _userLocation!.latitude,
                      _userLocation!.longitude,
                    )
                        : -1.0;
                    final isNearby = _userLocation != null && distance < 0.5;

                    return Marker(
                      width: 20,
                      height: 20,
                      point: LatLng(
                        stand['latitude']?.toDouble() ?? 0,
                        stand['longitude']?.toDouble() ?? 0,
                      ),
                      child: GestureDetector(
                        onTap: () => _showStandDetails(stand, distance),
                        child: Container(
                          decoration: BoxDecoration(
                            color: available > 0
                                ? (isNearby ? Colors.green : Colors.blue)
                                : Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '$available',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '📍 Nearby Stands',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (_userLocation != null)
                        Text(
                          '${_userLocation!.latitude.toStringAsFixed(4)}, ${_userLocation!.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: nearestStands.isEmpty
                      ? const Center(child: Text('No stands found nearby.'))
                      : ListView.builder(
                    itemCount: nearestStands.length,
                    itemBuilder: (context, index) {
                      final stand = nearestStands[index];
                      final cycles = stand['cycles'] as List? ?? [];
                      final available = cycles.where((c) => c['status'] == 'available').length;
                      final distance = _userLocation != null
                          ? _calculateDistance(
                        stand['latitude']?.toDouble() ?? 0,
                        stand['longitude']?.toDouble() ?? 0,
                        _userLocation!.latitude,
                        _userLocation!.longitude,
                      )
                          : -1.0;
                      final isNearby = distance > 0 && distance < 0.5;

                      return ListTile(
                        leading: Icon(
                          Icons.electric_bike,
                          color: available > 0 ? Colors.green : Colors.red,
                        ),
                        title: Text(stand['name'] ?? 'Unknown'),
                        subtitle: Text('$available available (${cycles.length} total)'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (distance > 0)
                              Text(
                                _formatDistance(distance),
                                style: TextStyle(
                                  color: isNearby ? Colors.green : Colors.grey,
                                  fontWeight: isNearby ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Icon(
                              isNearby ? Icons.check_circle : Icons.circle_outlined,
                              color: isNearby ? Colors.green : Colors.grey,
                            ),
                          ],
                        ),
                        onTap: () => _showStandDetails(stand, distance),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}