import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/stand_service.dart';

class AdminStandsTab extends StatefulWidget {
  const AdminStandsTab({super.key});

  @override
  State<AdminStandsTab> createState() => _AdminStandsTabState();
}

class _AdminStandsTabState extends State<AdminStandsTab> {
  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _stands = [];
  bool _isLoading = true;
  String? _selectedBlockId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // ✅ Fetch blocks using StandService (or direct query if missing)
      _blocks = await StandService.getBlocks();
      print('✅ Blocks loaded: ${_blocks.length}');

      if (_blocks.isNotEmpty) {
        _selectedBlockId = _blocks.first['id'];
        await _loadStands();
      }
    } catch (e) {
      print('❌ Error loading blocks: $e');
      // Fallback: direct Supabase query
      try {
        final response = await Supabase.instance.client
            .from('blocks')
            .select('*')
            .order('name');
        _blocks = List<Map<String, dynamic>>.from(response);
        print('✅ Blocks loaded (fallback): ${_blocks.length}');
        if (_blocks.isNotEmpty) {
          _selectedBlockId = _blocks.first['id'];
          await _loadStands();
        }
      } catch (e2) {
        print('❌ Fallback also failed: $e2');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadStands() async {
    if (_selectedBlockId == null) return;
    try {
      // ✅ Get stands for selected block
      _stands = await StandService.getStandsForBlock(_selectedBlockId!);
      print('✅ Stands loaded: ${_stands.length}');
    } catch (e) {
      print('❌ Error loading stands: $e');
      // Fallback: direct query
      try {
        final response = await Supabase.instance.client
            .from('stands')
            .select('*, cycles!stand_id(id, status, current_user_id, mac_address)')
            .eq('block_id', _selectedBlockId!)
            .order('name');
        _stands = List<Map<String, dynamic>>.from(response);
        print('✅ Stands loaded (fallback): ${_stands.length}');
      } catch (e2) {
        print('❌ Fallback stands failed: $e2');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading stands: $e2')),
          );
        }
      }
    }
  }

  Future<void> _allotCycle(String standId, String cycleId) async {
    final users = await Supabase.instance.client
        .from('profiles')
        .select('id, email')
        .neq('is_admin', true);

    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No users found.')),
      );
      return;
    }

    final selectedUser = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select User'),
        content: SizedBox(
          height: 200,
          width: 200,
          child: ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, i) {
              final user = users[i];
              return ListTile(
                title: Text(user['email']),
                onTap: () => Navigator.pop(context, user['id']),
              );
            },
          ),
        ),
      ),
    );
    if (selectedUser == null) return;

    await StandService.allotCycleToUser(cycleId, selectedUser);

    final userEmail = users.firstWhere((u) => u['id'] == selectedUser)['email'];
    await StandService.recordActivity(
      standId: standId,
      cycleId: cycleId,
      action: '',
      userId: selectedUser,
      userEmail: userEmail,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cycle allotted to $userEmail')),
    );
    _loadStands();
  }

  Future<void> _unallotCycle(String standId, String cycleId, String? userId, String userEmail) async {
    await StandService.makeCycleAvailable(cycleId);

    if (userId != null && userId.isNotEmpty) {
      await StandService.recordActivity(
        standId: standId,
        cycleId: cycleId,
        action: '',
        userId: userId,
        userEmail: userEmail,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cycle unallotted')),
    );
    _loadStands();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stand Management'),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blocks.isEmpty
          ? const Center(child: Text('No blocks found. Please add blocks in Supabase.'))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              value: _selectedBlockId,
              decoration: const InputDecoration(
                labelText: 'Select Block',
                border: OutlineInputBorder(),
              ),
              items: _blocks.map((block) {
                return DropdownMenuItem<String>(
                  value: block['id'],
                  child: Text(block['name'] ?? 'Unknown'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedBlockId = value;
                });
                if (value != null) {
                  _loadStands();
                }
              },
            ),
          ),
          Expanded(
            child: _stands.isEmpty
                ? const Center(child: Text('No stands found in this block.'))
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _stands.length,
              itemBuilder: (context, i) {
                final stand = _stands[i];
                final cycles = stand['cycles'] as List? ?? [];
                final cycle = cycles.isNotEmpty ? cycles.first : null;
                final isAllotted = cycle != null && cycle['status'] == 'in_use';
                final userEmail = cycle?['current_user_id'] ?? 'None';
                final cycleId = cycle?['id'] ?? 'No cycle';
                final macAddress = cycle?['mac_address'] ?? 'N/A';

                return StandCard(
                  stand: stand,
                  cycle: cycle,
                  isAllotted: isAllotted,
                  userEmail: userEmail,
                  cycleId: cycleId,
                  macAddress: macAddress,
                  onAllot: () => _allotCycle(stand['id'], cycle?['id'] ?? ''),
                  onUnallot: () => _unallotCycle(
                    stand['id'],
                    cycle?['id'] ?? '',
                    cycle?['current_user_id'],
                    userEmail,
                  ),
                  onRefresh: _loadStands,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== STAND CARD ====================
class StandCard extends StatefulWidget {
  final Map<String, dynamic> stand;
  final Map<String, dynamic>? cycle;
  final bool isAllotted;
  final String userEmail;
  final String cycleId;
  final String macAddress;
  final VoidCallback onAllot;
  final VoidCallback onUnallot;
  final VoidCallback onRefresh;

  const StandCard({
    super.key,
    required this.stand,
    required this.cycle,
    required this.isAllotted,
    required this.userEmail,
    required this.cycleId,
    required this.macAddress,
    required this.onAllot,
    required this.onUnallot,
    required this.onRefresh,
  });

  @override
  State<StandCard> createState() => _StandCardState();
}

class _StandCardState extends State<StandCard> {
  List<Map<String, dynamic>> _activities = [];
  bool _loadingActivities = false;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() => _loadingActivities = true);
    try {
      _activities = await StandService.getStandActivities(widget.stand['id']);
    } catch (e) {
      print('Error loading activities: $e');
    }
    setState(() => _loadingActivities = false);
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: widget.isAllotted ? Colors.orange : Colors.green,
          child: Icon(
            widget.isAllotted ? Icons.directions_bike : Icons.check_circle,
            color: Colors.white,
          ),
        ),
        title: Text(
          widget.stand['name'] ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          widget.isAllotted
              ? 'Allotted to: ${widget.userEmail}'
              : 'Available',
          style: TextStyle(
            color: widget.isAllotted ? Colors.orange : Colors.green,
          ),
        ),
        trailing: widget.isAllotted
            ? ElevatedButton.icon(
          onPressed: widget.onUnallot,
          icon: const Icon(Icons.remove_circle, size: 18),
          label: const Text('Unallot'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        )
            : ElevatedButton.icon(
          onPressed: widget.onAllot,
          icon: const Icon(Icons.add_circle, size: 18),
          label: const Text('Allot'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
        ),
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cycle Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text('Cycle ID: ${widget.cycleId}'),
                Text('MAC Address: ${widget.macAddress}'),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent Activities (Last 5)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                if (_loadingActivities)
                  const Center(child: CircularProgressIndicator())
                else if (_activities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No activities yet', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._activities.map((activity) => ListTile(
                    dense: true,
                    leading: Icon(
                      activity['action'] == 'allot' ? Icons.login : Icons.logout,
                      color: activity['action'] == 'allot' ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    title: Text(
                      '${activity['user_email']} ${activity['action']}ed',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      _formatTimestamp(activity['timestamp']),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  )),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}