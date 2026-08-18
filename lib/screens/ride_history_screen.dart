import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cycle_service.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadRideHistory();
  }

  Future<void> _loadRideHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final rides = await CycleService.getRideHistory();
      setState(() {
        _rides = rides;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading ride history: $e';
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoString;
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRideHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRideHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : _rides.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No rides yet.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Start your first ride!',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rides.length,
        itemBuilder: (context, index) {
          final ride = _rides[index];
          final cycleId = ride['cycle_id'] ?? 'N/A';
          final startStand = ride['start_stand']?['name'] ?? 'Unknown';
          final returnStand = ride['return_stand']?['name'] ?? 'In Progress';
          final startTime = ride['start_time'] ?? '';
          final endTime = ride['end_time']; // ✅ Get end time
          final duration = ride['duration'] ?? 0;
          final status = ride['status'] ?? 'active';

          final isActive = status == 'active';

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: CircleAvatar
                  CircleAvatar(
                    backgroundColor: isActive ? Colors.orange : Colors.green,
                    child: Icon(
                      isActive ? Icons.timelapse : Icons.check_circle,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Middle: Content (expanded)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cycle: $cycleId',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Start stand
                        Row(
                          children: [
                            const Icon(Icons.play_arrow, size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                startStand,
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (!isActive) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.stop, size: 14, color: Colors.red),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  returnStand,
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 4),
                        // ✅ Start Time
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              'Start: ${_formatTime(startTime)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        // ✅ End Time (only for completed rides)
                        if (!isActive && endTime != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                'End: ${_formatTime(endTime)}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                        // Duration
                        if (!isActive) ...[
                          Row(
                            children: [
                              const Icon(Icons.timer, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                'Duration: ${_formatDuration(duration)}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Right: Status Chip
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: isActive
                        ? const Chip(
                      label: Text('Active'),
                      backgroundColor: Colors.orange,
                      labelStyle: TextStyle(color: Colors.white, fontSize: 11),
                      padding: EdgeInsets.symmetric(horizontal: 4),
                    )
                        : const Chip(
                      label: Text('Completed'),
                      backgroundColor: Colors.green,
                      labelStyle: TextStyle(color: Colors.white, fontSize: 11),
                      padding: EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRideDetails(BuildContext context, Map<String, dynamic> ride) {
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
            const Text(
              'Ride Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _detailTile('Cycle ID', ride['cycle_id'] ?? 'N/A'),
            _detailTile('Start Stand', ride['start_stand']?['name'] ?? 'Unknown'),
            _detailTile('Return Stand', ride['return_stand']?['name'] ?? 'In Progress'),
            _detailTile('Start Time', _formatTime(ride['start_time'])),
            _detailTile('End Time', _formatTime(ride['end_time'])),
            _detailTile('Duration', _formatDuration(ride['duration'] ?? 0)),
            _detailTile('Status', ride['status'] ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _detailTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}