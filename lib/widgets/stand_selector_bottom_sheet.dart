import 'package:flutter/material.dart';

import '../core/errors/app_exception.dart';
import '../services/cycle_service.dart';

class StandSelection {
  const StandSelection({required this.standId, this.cycleId});

  final String standId;
  final String? cycleId;
}

Future<StandSelection?> showStandSelectorBottomSheet(
  BuildContext context, {
  required bool forReturn,
}) => showModalBottomSheet<StandSelection>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  barrierColor: Colors.black54,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => _StandSelector(forReturn: forReturn),
);

class _StandSelector extends StatefulWidget {
  const _StandSelector({required this.forReturn});

  final bool forReturn;

  @override
  State<_StandSelector> createState() => _StandSelectorState();
}

class _StandSelectorState extends State<_StandSelector> {
  final _service = CycleService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _stands = const [];
  String? _selectedBlock;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _blockName(Map<String, dynamic> stand) {
    final name = stand['name']?.toString().trim() ?? '';
    final match = RegExp(r'\s+stand\b', caseSensitive: false).firstMatch(name);
    if (match != null && match.start > 0)
      return name.substring(0, match.start).trim();
    final location = stand['location']?.toString().trim() ?? '';
    if (location.isNotEmpty && location.toLowerCase() != 'campus')
      return location;
    return name.isEmpty ? 'Other stands' : name;
  }

  Map<String, List<Map<String, dynamic>>> get _blocks {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final stand in _stands) {
      groups
          .putIfAbsent(_blockName(stand), () => <Map<String, dynamic>>[])
          .add(stand);
    }
    return groups;
  }

  List<Map<String, dynamic>> get _visibleStands {
    final block = _selectedBlock;
    if (block == null) return const [];
    final stands = _blocks[block] ?? const <Map<String, dynamic>>[];
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty || block.toLowerCase().contains(query)) return stands;
    return stands
        .where((stand) => _searchableStandText(stand).contains(query))
        .toList();
  }

  List<String> get _visibleBlocks {
    final query = _searchController.text.trim().toLowerCase();
    final blocks = _blocks.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (query.isEmpty) return blocks;
    return blocks.where((block) {
      if (block.toLowerCase().contains(query)) return true;
      return (_blocks[block] ?? const <Map<String, dynamic>>[]).any(
        (stand) => _searchableStandText(stand).contains(query),
      );
    }).toList();
  }

  String _searchableStandText(Map<String, dynamic> stand) => [
    stand['name'],
    stand['location'],
    stand['id'],
    stand['esp_mac'],
  ].whereType<Object>().join(' ').toLowerCase();

  List<dynamic> _cycles(Map<String, dynamic> stand) =>
      stand['cycles'] is List ? stand['cycles'] as List : const [];

  bool _isAvailable(dynamic cycle) =>
      cycle is Map &&
      cycle['status'] == 'available' &&
      cycle['physical_state'] == 'present';

  bool _isPresent(dynamic cycle) =>
      cycle is Map && cycle['physical_state'] == 'present';

  String _cycleState(dynamic cycle) {
    if (cycle is! Map) return 'Unknown';
    final physical = cycle['physical_state']?.toString();
    final status = cycle['status']?.toString();
    if (physical == 'absent') {
      if (status == 'in_use') return 'Absent · in ride';
      if (status == 'maintenance') return 'Absent · maintenance';
      return 'Absent';
    }
    if (physical == 'present') {
      if (status == 'maintenance') return 'Present · maintenance';
      if (status == 'disabled') return 'Present · disabled';
      if (status == 'in_use') return 'Present · in ride';
      return 'Present · available';
    }
    if (status == 'maintenance') return 'Unknown · maintenance';
    return 'Physical state unknown';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Keep every active stand visible. The ride operation performs its
      // exact-BSSID ESP inventory check after the user selects a stand.
      _stands = await _service.getStands();
    } on AppException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectBlock(String block) {
    setState(() {
      _selectedBlock = block;
      _searchController.clear();
    });
  }

  void _goBackToBlocks() {
    setState(() {
      _selectedBlock = null;
      _searchController.clear();
    });
  }

  Future<void> _choose(Map<String, dynamic> stand) async {
    if (widget.forReturn) {
      Navigator.pop(context, StandSelection(standId: stand['id'].toString()));
      return;
    }

    final availableAtSnapshot = _cycles(stand).where(_isAvailable).toList();
    if (availableAtSnapshot.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No physically available cycle at this stand.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final cycles = await _service.getAvailableCyclesAtStand(
        stand['id'].toString(),
      );
      if (!mounted) return;
      if (cycles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No physically available cycle at this stand. Refresh and try again.',
            ),
          ),
        );
        return;
      }
      final cycle = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              ListTile(
                leading: const Icon(Icons.pedal_bike),
                title: const Text('Choose a cycle'),
                subtitle: Text(stand['name']?.toString() ?? 'Selected stand'),
              ),
              ...cycles.map(
                (item) => ListTile(
                  leading: const Icon(Icons.pedal_bike_outlined),
                  title: Text(
                    item['cycle_number']?.toString() ?? item['id'].toString(),
                  ),
                  subtitle: const Text('Present · available'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, item),
                ),
              ),
            ],
          ),
        ),
      );
      if (mounted && cycle != null) {
        Navigator.pop(
          context,
          StandSelection(
            standId: stand['id'].toString(),
            cycleId: cycle['id'].toString(),
          ),
        );
      }
    } on AppException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _cycleSummary(Map<String, dynamic> stand) {
    final cycles = _cycles(stand);
    if (cycles.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text(
          'No cycle assigned · stand is empty',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cycles.map((cycle) {
        final number = cycle is Map ? cycle['cycle_number']?.toString() : null;
        final label = number == null || number.isEmpty
            ? 'Cycle'
            : 'Cycle $number';
        final state = _cycleState(cycle);
        final color = state.startsWith('Present · available')
            ? Colors.green.shade700
            : state.startsWith('Absent')
            ? Colors.deepOrange.shade700
            : Colors.orange.shade800;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                state.startsWith('Present')
                    ? Icons.circle
                    : Icons.circle_outlined,
                size: 10,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$label · $state', style: TextStyle(color: color)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _standTile(Map<String, dynamic> stand) {
    final cycles = _cycles(stand);
    final available = cycles.where(_isAvailable).length;
    final present = cycles.where(_isPresent).length;
    final hasSelectableCycle = available > 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: const Color(0xfff5f8f5),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        leading: Icon(
          widget.forReturn ? Icons.lock_outline : Icons.storefront_outlined,
          color: Colors.green.shade700,
        ),
        title: Text(
          stand['name']?.toString() ?? 'Unnamed stand',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${stand['location'] ?? 'Campus'} · $available available · $present present · capacity ${stand['capacity'] ?? '—'}',
            ),
            _cycleSummary(stand),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.forReturn || hasSelectableCycle
            ? () => _choose(stand)
            : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No physically available cycle at this stand.'),
                ),
              ),
      ),
    );
  }

  Widget _blockTile(String block) {
    final stands = _blocks[block] ?? const <Map<String, dynamic>>[];
    final cycles = stands.expand(_cycles).toList();
    final available = cycles.where(_isAvailable).length;
    final present = cycles.where(_isPresent).length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      elevation: 0,
      color: const Color(0xfff5f8f5),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        leading: Icon(
          Icons.location_city_outlined,
          color: Colors.green.shade700,
          size: 30,
        ),
        title: Text(
          block,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${stands.length} stands · $available available · $present present',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _selectBlock(block),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingBlock = _selectedBlock != null;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
            child: Row(
              children: [
                if (showingBlock)
                  IconButton(
                    tooltip: 'Back to blocks',
                    onPressed: _loading ? null : _goBackToBlocks,
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    showingBlock
                        ? _selectedBlock!
                        : widget.forReturn
                        ? 'Choose a return block'
                        : 'Choose a block',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _searchController,
              enabled: !_loading,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: showingBlock
                    ? 'Search in this block'
                    : 'Search block or stand',
                hintText: showingBlock
                    ? 'e.g. Stand 7'
                    : 'e.g. Admin, Hostel or T/P',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _stands.isEmpty
                ? Center(
                    child: Text(
                      widget.forReturn
                          ? 'No active stands are currently available.'
                          : 'No active stands are available.',
                    ),
                  )
                : showingBlock
                ? _visibleStands.isEmpty
                      ? Center(
                          child: Text(
                            'No stand matches “${_searchController.text.trim()}”.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _visibleStands.length,
                          itemBuilder: (_, index) =>
                              _standTile(_visibleStands[index]),
                        )
                : _visibleBlocks.isEmpty
                ? Center(
                    child: Text(
                      'No block or stand matches “${_searchController.text.trim()}”.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _visibleBlocks.length,
                    itemBuilder: (_, index) =>
                        _blockTile(_visibleBlocks[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
