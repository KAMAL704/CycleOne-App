import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class OSMMap extends StatefulWidget {
  final List<LatLng>? polylinePoints;
  final void Function(LatLng)? onTap;

  const OSMMap({super.key, this.polylinePoints, this.onTap});

  @override
  State<OSMMap> createState() => _OSMMapState();
}

class _OSMMapState extends State<OSMMap> {
  late MapController _mapController;
  LatLng _currentLocation = const LatLng(0, 0);
  bool _locationLoaded = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse) return;
    }
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      _locationLoaded = true;
    });
    _mapController.move(_currentLocation, 15);
  }

  void _centerMap() {
    if (_locationLoaded) {
      _mapController.move(_currentLocation, 15);
    } else {
      _getCurrentLocation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentLocation,
            initialZoom: 13,
            onTap: (tapPosition, point) => widget.onTap?.call(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.cycleone',
            ),
            if (widget.polylinePoints != null && widget.polylinePoints!.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.polylinePoints!,
                    color: Colors.blue,
                    strokeWidth: 4,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  width: 80,
                  height: 80,
                  point: _currentLocation,
                  child: const Icon(Icons.my_location, color: Colors.red, size: 40),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: _centerMap,
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}