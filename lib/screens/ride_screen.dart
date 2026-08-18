import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../providers/cycle_provider.dart';
import '../services/ride_service.dart';
import '../widgets/osm_map.dart';

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  final RideService _rideService = RideService();
  bool _isRiding = false;
  LatLng? _currentLocation;
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _checkActiveRide();
    _startLocationUpdates();
  }

  void _checkActiveRide() async {
    final cycleProvider = context.read<CycleProvider>();
    setState(() {
      _isRiding = cycleProvider.hasCycle;
    });
  }

  void _startLocationUpdates() {
    Geolocator.getPositionStream().listen((Position position) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        if (_isRiding) {
          _routePoints.add(_currentLocation!);
        }
      });
    });
  }

  Future<void> _startRide() async {
    final cycleProvider = context.read<CycleProvider>();
    if (!cycleProvider.hasCycle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No cycle allocated. Scan QR first.')),
      );
      return;
    }
    await _rideService.startRide(cycleProvider.currentCycleId!);
    setState(() {
      _isRiding = true;
      _routePoints.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride started! Map tracking your path.')),
    );
  }

  Future<void> _endRide() async {
    final cycleProvider = context.read<CycleProvider>();
    if (!cycleProvider.hasCycle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active ride to end.')),
      );
      return;
    }
    await _rideService.endRide();
    cycleProvider.returnCycle();
    setState(() => _isRiding = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride ended. Path saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Ride Map'),
        actions: [
          IconButton(
            icon: Icon(_isRiding ? Icons.stop : Icons.play_arrow),
            onPressed: _isRiding ? _endRide : _startRide,
          ),
        ],
      ),
      body: OSMMap(
        polylinePoints: _routePoints,
        onTap: (point) {
          print('Tapped at: $point');
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!_isRiding)
            FloatingActionButton(
              heroTag: 'start',
              onPressed: _startRide,
              child: const Icon(Icons.play_arrow),
            ),
          if (_isRiding)
            FloatingActionButton(
              heroTag: 'end',
              onPressed: _endRide,
              backgroundColor: Colors.red,
              child: const Icon(Icons.stop),
            ),
        ],
      ),
    );
  }
}