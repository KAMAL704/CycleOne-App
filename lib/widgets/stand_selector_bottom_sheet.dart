import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cycle_service.dart';

class StandSelectorContent extends StatefulWidget {
  final bool forReturn;
  const StandSelectorContent({super.key, required this.forReturn});

  @override
  State<StandSelectorContent> createState() => _StandSelectorContentState();
}

class _StandSelectorContentState extends State<StandSelectorContent> {
  List<Map<String, dynamic>> _blocks = [];
  List<Map<String, dynamic>> _stands = [];
  List<Map<String, dynamic>> _cycles = [];
  bool _isLoading = true;
  String? _selectedBlockId;
  String? _selectedStandId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final blocksResponse = await Supabase.instance.client
          .from('blocks')
          .select('*')
          .order('name');
      _blocks = List<Map<String, dynamic>>.from(blocksResponse);

      if (_blocks.isNotEmpty) {
        _selectedBlockId = _blocks.first['id'];
        await _loadStands();
      }
    } catch (e) {
      print('Error loading data: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadStands() async {
    if (_selectedBlockId == null) return;
    try {
      final query = Supabase.instance.client
          .from('stands')
          .select('*, cycles!stand_id(id, status, mac_address)')
          .eq('block_id', _selectedBlockId!)
          .order('name');

      final response = await query;
      _stands = List<Map<String, dynamic>>.from(response);

      if (!widget.forReturn) {
        _stands = _stands.where((stand) {
          final cycles = stand['cycles'] as List?;
          if (cycles == null) return false;
          return cycles.any((c) => c['status'] == 'available');
        }).toList();
      }

      setState(() {});
    } catch (e) {
      print('Error loading stands: $e');
    }
  }

  Future<void> _loadCyclesForStand(String standId) async {
    setState(() => _isLoading = true);
    try {
      if (widget.forReturn) {
        _cycles = [];
      } else {
        final response = await Supabase.instance.client
            .from('cycles')
            .select('id, mac_address, status')
            .eq('stand_id', standId)
            .eq('status', 'available');
        _cycles = List<Map<String, dynamic>>.from(response);
      }
      setState(() {});
    } catch (e) {
      print('Error loading cycles: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Text(
            widget.forReturn ? 'Select Stand to Return' : 'Select Stand & Cycle',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_selectedStandId == null) ...[
            // Block Selector
            DropdownButtonFormField<String>(
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
                  _selectedStandId = null;
                });
                if (value != null) {
                  _loadStands();
                }
              },
            ),
            const SizedBox(height: 12),
            Text(
              widget.forReturn ? 'Choose a stand:' : 'Choose a stand:',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _stands.isEmpty
                  ? Center(
                child: Text(
                  widget.forReturn
                      ? 'No stands in this block.'
                      : 'No available cycles in this block.',
                ),
              )
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                itemCount: _stands.length,
                itemBuilder: (context, index) {
                  final stand = _stands[index];
                  final cycles = stand['cycles'] as List?;
                  final hasCycle = cycles?.isNotEmpty ?? false;

                  return Card(
                    color: hasCycle ? Colors.green.shade50 : Colors.grey.shade100,
                    child: InkWell(
                      onTap: () {
                        if (widget.forReturn) {
                          Navigator.pop(context, {
                            'cycleId': null,
                            'standId': stand['id'],
                          });
                        } else {
                          if (hasCycle) {
                            setState(() {
                              _selectedStandId = stand['id'];
                            });
                            _loadCyclesForStand(stand['id']);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No available cycles at this stand.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              hasCycle ? Icons.storefront : Icons.storefront,
                              size: 40,
                              color: hasCycle ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              stand['name'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              hasCycle ? 'Has cycle' : 'Empty',
                              style: TextStyle(
                                fontSize: 12,
                                color: hasCycle ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            // Show cycles
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedStandId = null;
                      _cycles = [];
                    });
                  },
                ),
                const Text(
                  'Select a cycle:',
                  style: TextStyle(fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${_cycles.length} available',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _cycles.isEmpty
                  ? const Center(child: Text('No available cycles at this stand.'))
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _cycles.length,
                itemBuilder: (context, index) {
                  final cycle = _cycles[index];
                  return Card(
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context, {
                          'cycleId': cycle['id'],
                          'standId': _selectedStandId,
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.directions_bike, size: 40, color: Colors.green),
                              const SizedBox(height: 8),
                              Text(
                                cycle['id'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                                textAlign: TextAlign.center,
                              ),
                              if (cycle['mac_address'] != null)
                                Text(
                                  cycle['mac_address'],
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// SHOW STAND SELECTOR BOTTOM SHEET
// ============================================================

Future<Map<String, String>?> showStandSelectorBottomSheet(
    BuildContext context, {
      required bool forReturn,
    }) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => StandSelectorContent(forReturn: forReturn),
  );

  if (result != null) {
    final map = <String, String>{};
    if (result['cycleId'] != null) {
      map['cycleId'] = result['cycleId'] as String;
    }
    if (result['standId'] != null) {
      map['standId'] = result['standId'] as String;
    }
    return map;
  }
  return null;
}