class CycleAllocation {
  final String? cycleId;

  CycleAllocation({this.cycleId});

  bool get hasCycle => cycleId != null;

  CycleAllocation copyWith({String? cycleId}) {
    return CycleAllocation(cycleId: cycleId ?? this.cycleId);
  }
}