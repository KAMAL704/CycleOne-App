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

  List<Map<String, dynamic>> get _visibleStands {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _stands;
    return _stands.where((stand) {
      final searchable = [
        stand['name'],
        stand['location'],
        stand['id'],
        stand['esp_mac'],
      ].whereType<Object>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Keep every active stand visible. The ride operation performs its
      // exact-BSSID ESP inventory check after the user selects a stand, so an
      // unverified stand can become available without being hidden upfront.
      _stands = await _service.getStands();
    } on AppException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(Map<String, dynamic> stand) async {
    setState(() => _loading = true);
    try {
      if (widget.forReturn) {
        if (mounted)
          Navigator.pop(
            context,
            StandSelection(standId: stand['id'].toString()),
          );
        return;
      }
      final cycles = await _service.getAvailableCyclesAtStand(
        stand['id'].toString(),
      );
      if (!mounted) return;
      final cycle = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: Colors.white,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => ListView(
          children: [
            const ListTile(title: Text('Choose a cycle')),
            ...cycles.map(
              (item) => ListTile(
                leading: const Icon(Icons.pedal_bike),
                title: Text(
                  item['cycle_number']?.toString() ?? item['id'].toString(),
                ),
                onTap: () => Navigator.pop(context, item),
              ),
            ),
          ],
        ),
      );
      if (mounted && cycle != null)
        Navigator.pop(
          context,
          StandSelection(
            standId: stand['id'].toString(),
            cycleId: cycle['id'].toString(),
          ),
        );
    } on AppException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .72,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.forReturn ? 'Choose a return stand' : 'Choose a stand',
                  style: Theme.of(context).textTheme.titleLarge,
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
              labelText: 'Search stand number',
              hintText: 'e.g. 7 or Science Block Stand 7',
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
                        ? 'No return stands are currently available.'
                        : 'No cycles are available.',
                  ),
                )
              : _visibleStands.isEmpty
              ? Center(
                  child: Text(
                    'No stand matches “${_searchController.text.trim()}”.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: _visibleStands.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final stand = _visibleStands[index];
                    final cycles = stand['cycles'] as List? ?? const [];
                    final available = cycles
                        .where(
                          (cycle) =>
                              cycle is Map &&
                              cycle['status'] == 'available' &&
                              cycle['physical_state'] == 'present',
                        )
                        .length;
                    return ListTile(
                      leading: Icon(
                        widget.forReturn
                            ? Icons.lock_outline
                            : Icons.pedal_bike,
                      ),
                      title: Text(stand['name']?.toString() ?? 'Unnamed stand'),
                      subtitle: Text(
                        '${stand['location'] ?? 'Campus'} · $available available · ${cycles.length}/${stand['capacity'] ?? '—'} slots',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _choose(stand),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
