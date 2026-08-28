import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AdminStandsTab extends StatefulWidget {
  const AdminStandsTab({super.key});

  @override
  State<AdminStandsTab> createState() => _AdminStandsTabState();
}

class _AdminStandsTabState extends State<AdminStandsTab> {
  final _client = Supabase.instance.client;
  final _uuid = const Uuid();
  List<Map<String, dynamic>> _stands = const [];
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
      final rows = await _client.from('stands').select('*, cycles(id, status, physical_state)').order('name');
      if (mounted) setState(() => _stands = List<Map<String, dynamic>>.from(rows));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load stands: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? stand]) async {
    final name = TextEditingController(text: stand?['name']?.toString() ?? '');
    final location = TextEditingController(text: stand?['location']?.toString() ?? '');
    final mac = TextEditingController(text: stand?['esp_mac']?.toString() ?? '');
    final ssid = TextEditingController(text: stand?['esp_ssid']?.toString() ?? 'CycleOneS1');
    final password = TextEditingController(text: stand?['esp_password']?.toString() ?? 'CycleOne');
    final ip = TextEditingController(text: stand?['esp_ip']?.toString() ?? '10.10.10.10');
    final port = TextEditingController(text: stand?['esp_port']?.toString() ?? '80');
    final capacity = TextEditingController(text: stand?['capacity']?.toString() ?? '1');
    final latitude = TextEditingController(text: stand?['latitude']?.toString() ?? '');
    final longitude = TextEditingController(text: stand?['longitude']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
          title: Text(stand == null ? 'Add stand' : 'Edit stand'),
          content: SizedBox(width: 420, child: Form(key: formKey, child: SingleChildScrollView(child: Column(children: [
            _field(name, 'Name', required: true),
            _field(location, 'Location'),
            _field(mac, 'ESP MAC (AA:BB:CC:DD:EE:FF)', required: true),
            _field(ssid, 'ESP Wi-Fi SSID', required: true),
            _field(password, 'ESP Wi-Fi password', required: true),
            _field(ip, 'ESP IP', required: true),
            _field(port, 'ESP port', keyboard: TextInputType.number, required: true),
            _field(capacity, 'Capacity', keyboard: TextInputType.number, required: true),
            _field(latitude, 'Latitude', keyboard: const TextInputType.numberWithOptions(decimal: true)),
            _field(longitude, 'Longitude', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          ])))),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Save'))],
        ));
    if (saved != true) { for (final c in [name, location, mac, ssid, password, ip, port, capacity, latitude, longitude]) c.dispose(); return; }
    final normalizedMac = mac.text.trim().toUpperCase();
    final values = <String, dynamic>{
      'name': name.text.trim(), 'location': location.text.trim(), 'esp_mac': normalizedMac,
      'esp_ssid': ssid.text.trim(), 'esp_password': password.text,
      'esp_ip': ip.text.trim(), 'esp_port': int.tryParse(port.text.trim()) ?? 80,
      'capacity': int.tryParse(capacity.text.trim()) ?? 1,
      'latitude': double.tryParse(latitude.text.trim()), 'longitude': double.tryParse(longitude.text.trim()),
    };
    try {
      if (stand == null) {
        values['id'] = _uuid.v4();
        await _client.from('stands').insert(values);
      } else {
        await _client.from('stands').update(values).eq('id', stand['id']);
      }
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save stand: $error')));
    } finally {
      for (final c in [name, location, mac, ssid, password, ip, port, capacity, latitude, longitude]) c.dispose();
    }
  }

  Widget _field(TextEditingController controller, String label, {bool required = false, TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(controller: controller, keyboardType: keyboard, obscureText: label.contains('password'), decoration: InputDecoration(labelText: label), validator: required ? (value) => value == null || value.trim().isEmpty ? 'Required' : null : null),
      );

  Future<void> _toggle(Map<String, dynamic> stand) async {
    final next = stand['status'] == 'active' ? 'disabled' : 'active';
    if (next == 'active' && (stand['esp_ssid'] == null || stand['esp_ssid'] == 'UNCONFIGURED' || stand['esp_password'] == null || stand['esp_password'] == 'UNCONFIGURED')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configure the ESP BSSID, SSID and password before enabling this stand.')));
      return;
    }
    try { await _client.from('stands').update({'status': next}).eq('id', stand['id']); await _load(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update stand: $error'))); }
  }

  Future<void> _remove(Map<String, dynamic> stand) async {
    try {
      await _client.from('stands').update({'status': 'disabled'}).eq('id', stand['id']);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove stand: $error')));
    }
  }

  void _showQr(Map<String, dynamic> stand) => showDialog<void>(context: context, builder: (_) => AlertDialog(
        title: Text('QR · ${stand['name']}'),
        content: QrImageView(data: 'cycleone://stand/${stand['id']}', size: 220),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(onPressed: _loading ? null : () => _edit(), icon: const Icon(Icons.add), label: const Text('Stand')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : RefreshIndicator(onRefresh: _load, child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _stands.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final stand = _stands[index];
                      final cycles = (stand['cycles'] as List?)?.whereType<Map>().toList() ?? const [];
                      final available = cycles.where((cycle) => cycle['status'] == 'available').length;
                      final active = stand['status'] == 'active';
                      return Card(child: ListTile(
                        leading: Icon(Icons.storefront, color: active ? Colors.green : Colors.grey),
                        title: Text(stand['name'].toString()),
                        subtitle: Text('${stand['location'] ?? 'Campus'} · $available available · capacity ${stand['capacity']}\n${stand['esp_mac']}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(onSelected: (action) { if (action == 'edit') _edit(stand); if (action == 'qr') _showQr(stand); if (action == 'toggle') _toggle(stand); if (action == 'remove') _remove(stand); }, itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'qr', child: Text('Show QR')), PopupMenuItem(value: 'toggle', child: Text(active ? 'Disable' : 'Enable')), const PopupMenuItem(value: 'remove', child: Text('Remove stand'))]),
                      ));
                    },
                  )),
      );
}
