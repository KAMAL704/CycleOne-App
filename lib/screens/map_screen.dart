import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../services/stand_service.dart';
import '../core/errors/app_exception.dart';
import '../core/logging/app_logger.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _standService = StandService();
  List<Map<String, dynamic>> _stands = [];
  LatLng? _userLocation;
  bool _isLoading = true;
  bool _locationPermissionDenied = false;
  String? _error;
  GoogleMapController? _mapController;
  static const _campusCenter = LatLng(30.1756, 76.7894);

  @override
  void initState() {
    super.initState();
    _loadStands();
  }

  Future<void> _loadStands() async {
    setState(() => _isLoading = true);
    try {
      _stands = await _standService.getStands();
      await _getUserLocation();
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (e) {
      if (mounted)
        setState(
          () => _error =
              'Could not load stands. Check your connection and try again.',
        );
    }
    if (mounted) setState(() => _isLoading = false);
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
        if (_userLocation != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(_userLocation!, 15),
          );
        }
      });
    } catch (e) {
      AppLogger.error('MAP', e);
      setState(() => _locationPermissionDenied = true);
    }
  }

  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371;
    double dLat = _toRadians(lat1 - lat2);
    double dLng = _toRadians(lng1 - lng2);
    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat2)) *
            cos(_toRadians(lat1)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * pi / 180;

  String _formatDistance(double distanceKm) {
    if (distanceKm < 0) return 'Location unavailable';
    if (distanceKm < 1.0) {
      final meters = (distanceKm * 1000).round();
      return '$meters m';
    } else {
      return '${distanceKm.toStringAsFixed(1)} km';
    }
  }

  List<Map<String, dynamic>> _getNearestStands() {
    final withCoordinates = _stands
        .where((stand) => stand['latitude'] is num && stand['longitude'] is num)
        .toList();
    if (_userLocation == null) return withCoordinates;
    return List.from(withCoordinates)..sort((a, b) {
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

  Future<void> _showStandDetails(
    Map<String, dynamic> stand,
    double distance,
  ) async {
    final cycles = stand['cycles'] as List? ?? [];
    final available = cycles.where(_isAvailableCycle).length;
    final activityFuture = _standService.getRecentActivity(
      stand['id'].toString(),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .64,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.electric_bike, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stand['name'] ?? 'Unknown Stand',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.directions_bike),
                title: const Text('Available Cycles'),
                trailing: Text('$available / ${cycles.length}'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on),
                title: const Text('Distance from you'),
                trailing: Text(_formatDistance(distance)),
              ),
              const SizedBox(height: 4),
              Text(
                'Last 5 stand activities',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: activityFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Activity is unavailable right now.'),
                      );
                    }
                    final activities =
                        snapshot.data ?? const <Map<String, dynamic>>[];
                    if (activities.isEmpty) {
                      return const Center(
                        child: Text('No ride activity recorded yet.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: activities.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final activity = activities[index];
                        final isReturn =
                            activity['action']?.toString().toLowerCase() ==
                            'return';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                (isReturn ? Colors.blue : Colors.green)
                                    .withAlpha(28),
                            child: Icon(
                              isReturn ? Icons.login : Icons.logout,
                              color: isReturn ? Colors.blue : Colors.green,
                            ),
                          ),
                          title: Text(
                            '${activity['action'] ?? 'Ride'} · ${activity['cycle_number'] ?? 'Cycle'}',
                          ),
                          subtitle: Text(
                            '${activity['user_label'] ?? 'CycleOne rider'} · ${_formatActivityTime(activity['activity_at'])}',
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatActivityTime(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? 'Time unavailable'
        : DateFormat('dd MMM, hh:mm a').format(parsed.toLocal());
  }

  bool _isAvailableCycle(dynamic cycle) =>
      cycle is Map &&
      cycle['status'] == 'available' &&
      cycle['physical_state'] == 'present';

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Find cycle stands')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 56),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadStands,
                  child: const Text('Retry'),
                ),
              ],
            ),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStands),
        ],
      ),
      body: Column(
        children: [
          if (_locationPermissionDenied)
            MaterialBanner(
              content: const Text(
                'Location is unavailable; showing all campus stands.',
              ),
              leading: const Icon(Icons.location_off),
              actions: [
                TextButton(
                  onPressed: _getUserLocation,
                  child: const Text('Grant'),
                ),
              ],
            ),
          Expanded(
            flex: 2,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _userLocation ?? _campusCenter,
                zoom: 14,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_userLocation != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_userLocation!, 15),
                  );
                }
              },
              myLocationEnabled: _userLocation != null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              markers: nearestStands.map((stand) {
                final cycles = stand['cycles'] as List? ?? [];
                final available = cycles.where(_isAvailableCycle).length;
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
                  markerId: MarkerId(stand['id'].toString()),
                  position: LatLng(
                    stand['latitude']?.toDouble() ?? 0,
                    stand['longitude']?.toDouble() ?? 0,
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    available > 0
                        ? (isNearby
                              ? BitmapDescriptor.hueGreen
                              : BitmapDescriptor.hueAzure)
                        : BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: stand['name']?.toString() ?? 'Cycle stand',
                    snippet: '$available cycle(s) available',
                  ),
                  onTap: () => _showStandDetails(stand, distance),
                );
              }).toSet(),
            ),
          ),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(225),
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_userLocation != null)
                        Text(
                          '${_userLocation!.latitude.toStringAsFixed(4)}, ${_userLocation!.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
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
                            final available = cycles
                                .where(_isAvailableCycle)
                                .length;
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
                                color: available > 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              title: Text(stand['name'] ?? 'Unknown'),
                              subtitle: Text(
                                '$available available (${cycles.length} total)',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (distance > 0)
                                    Text(
                                      _formatDistance(distance),
                                      style: TextStyle(
                                        color: isNearby
                                            ? Colors.green
                                            : Colors.grey,
                                        fontWeight: isNearby
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isNearby
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color: isNearby
                                        ? Colors.green
                                        : Colors.grey,
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
