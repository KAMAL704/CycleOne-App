import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class RideService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _currentRideId;

  Future<void> startRide(String cycleId) async {
    Position position = await Geolocator.getCurrentPosition();
    final response = await _supabase.from('rides').insert({
      'user_id': _supabase.auth.currentUser!.id,
      'cycle_id': cycleId,
      'start_lat': position.latitude,
      'start_lng': position.longitude,
      'status': 'active',
    }).select();
    _currentRideId = response.first['id'];
  }

  Future<void> endRide() async {
    if (_currentRideId == null) return;
    Position position = await Geolocator.getCurrentPosition();
    await _supabase.from('rides').update({
      'end_time': DateTime.now().toIso8601String(),
      'end_lat': position.latitude,
      'end_lng': position.longitude,
      'status': 'completed',
    }).eq('id', _currentRideId!);
    _currentRideId = null;
  }

  Future<List<Map<String, dynamic>>> getRideHistory() async {
    final response = await _supabase.from('rides')
        .select()
        .eq('user_id', _supabase.auth.currentUser!.id)
        .order('start_time', ascending: false);
    return response;
  }

  Future<double> calculateDistance(LatLng start, LatLng end) async {
    return Geolocator.distanceBetween(start.latitude, start.longitude, end.latitude, end.longitude) / 1000;
  }
}