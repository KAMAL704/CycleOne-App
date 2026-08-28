import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum PendingOperationType { start, end }

class PendingOperation {
  const PendingOperation({required this.type, required this.cycleId, required this.standId, required this.userId, this.rideId});

  final PendingOperationType type;
  final String cycleId;
  final String standId;
  final String userId;
  final String? rideId;

  bool matches(PendingOperationType requestedType, String requestedCycleId, String requestedStandId, String requestedUserId) =>
      type == requestedType && cycleId == requestedCycleId && standId == requestedStandId && userId == requestedUserId;

  Map<String, String> toJson() => {
        'type': type.name,
        'cycleId': cycleId,
        'standId': standId,
        'userId': userId,
        'rideId': ?rideId,
      };

  static PendingOperation? fromJson(Map<String, dynamic> json) {
    final values = PendingOperationType.values.where((value) => value.name == json['type']);
    final cycleId = json['cycleId']?.toString();
    final standId = json['standId']?.toString();
    final userId = json['userId']?.toString();
    if (values.isEmpty || cycleId == null || standId == null || userId == null) return null;
    return PendingOperation(type: values.first, cycleId: cycleId, standId: standId, userId: userId, rideId: json['rideId']?.toString());
  }
}

class PendingOperationStore {
  static const _key = 'cycleone.pending_hardware_operation.v1';

  Future<PendingOperation?> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    if (value == null) return null;
    try {
      return PendingOperation.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PendingOperation operation) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(operation.toJson()));

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}
