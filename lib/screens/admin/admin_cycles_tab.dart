import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCyclesTab extends StatefulWidget {
  const AdminCyclesTab({super.key});

  @override
  State<AdminCyclesTab> createState() => _AdminCyclesTabState();
}

class _AdminCyclesTabState extends State<AdminCyclesTab> {
  List<Map<String, dynamic>> _cycles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCycles();
  }

  Future<void> _fetchCycles() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('cycles')
          .select('*');
      _cycles = List<Map<String, dynamic>>.from(response);
      print('Cycles loaded: ${_cycles.length}');
    } catch (e) {
      print('Error loading cycles: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycles'),
        backgroundColor: Colors.green.shade700,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cycles.isEmpty
          ? const Center(child: Text('No cycles found.'))
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _cycles.length,
        itemBuilder: (context, i) {
          final cycle = _cycles[i];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: Text(cycle['id'] ?? 'No ID'),
              subtitle: Text(
                'Status: ${cycle['status'] ?? 'N/A'}\n'
                    'MAC: ${cycle['mac_address'] ?? 'N/A'}',
              ),
            ),
          );
        },
      ),
    );
  }
}