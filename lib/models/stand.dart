import 'dart:math';

class Stand {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int totalCycles;
  final int availableCycles;
  final List<StandActivity> recentActivities;

  Stand({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.totalCycles = 10,
    this.availableCycles = 0,
    this.recentActivities = const [],
  });

  bool get hasAvailableCycles => availableCycles > 0;

  double distanceTo(double userLat, double userLng) {
    const double earthRadius = 6371;
    double dLat = _toRadians(latitude - userLat);
    double dLng = _toRadians(longitude - userLng);
    double a = pow(sin(dLat / 2), 2) +
        cos(_toRadians(userLat)) * cos(_toRadians(latitude)) *
            pow(sin(dLng / 2), 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * pi / 180;

  factory Stand.fromJson(Map<String, dynamic> json) {
    return Stand(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      totalCycles: json['total_cycles'] ?? 10,
      availableCycles: json['available_cycles'] ?? 0,
    );
  }
}

class StandActivity {
  final String id;
  final String standId;
  final String cycleId;
  final String userId;
  final String userEmail;
  final String action;
  final DateTime timestamp; // This will be in local time after parsing

  StandActivity({
    required this.id,
    required this.standId,
    required this.cycleId,
    required this.userId,
    required this.userEmail,
    required this.action,
    required this.timestamp,
  });

  factory StandActivity.fromJson(Map<String, dynamic> json) {
    // Parse the UTC timestamp and convert to local time (IST)
    final utcTime = DateTime.parse(json['timestamp']);
    final localTime = utcTime.toLocal(); // Convert to device's local timezone
    return StandActivity(
      id: json['id'] ?? '',
      standId: json['stand_id'] ?? '',
      cycleId: json['cycle_id'] ?? '',
      userId: json['user_id'] ?? '',
      userEmail: json['user_email'] ?? 'Unknown',
      action: json['action'] ?? 'unknown',
      timestamp: localTime,
    );
  }
}