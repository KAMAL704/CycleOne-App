import 'package:flutter/material.dart';

import '../core/errors/app_exception.dart';
import '../services/cycle_service.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  final _service = CycleService();
  List<Map<String, dynamic>> _rides = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final rides = await _service.getRideHistory();
      if (mounted) setState(() => _rides = rides);
    } on AppException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return '—';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _duration(Map<String, dynamic> ride) {
    final started = DateTime.tryParse(ride['started_at']?.toString() ?? '');
    final ended = DateTime.tryParse(ride['ended_at']?.toString() ?? '');
    if (started == null || ended == null) return '—';
    final minutes = ended.difference(started).inMinutes;
    return minutes < 60 ? '$minutes min' : '${minutes ~/ 60}h ${minutes % 60}m';
  }

  Map<String, dynamic>? _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride history'), actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _rides.isEmpty
                  ? const Center(child: Text('No rides yet. Start a ride to see it here.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rides.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final ride = _rides[index];
                          final cycle = _map(ride['cycles']);
                          final start = _map(ride['start_stand']);
                          final end = _map(ride['end_stand']);
                          final active = ride['status'] == 'active';
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: active ? Colors.orange.shade100 : Colors.green.shade100,
                                child: Icon(active ? Icons.timelapse : Icons.check, color: active ? Colors.orange : Colors.green),
                              ),
                              title: Text('Cycle ${cycle?['cycle_number'] ?? ride['cycle_id'] ?? '—'}'),
                              subtitle: Text('${start?['name'] ?? 'Unknown stand'} → ${end?['name'] ?? (active ? 'In progress' : '—')}\n'
                                  'Started ${_date(ride['started_at'])}${active ? '' : ' · ${_duration(ride)}'}'),
                              isThreeLine: true,
                              trailing: Chip(label: Text(active ? 'Active' : (ride['status']?.toString() ?? 'Completed'))),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}
