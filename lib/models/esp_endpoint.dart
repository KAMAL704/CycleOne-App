import '../core/errors/app_exception.dart';

class EspEndpoint {
  const EspEndpoint({
    required this.mac,
    required this.ssid,
    required this.password,
    required this.host,
    required this.port,
  });

  final String mac;
  final String ssid;
  final String password;
  final String host;
  final int port;

  factory EspEndpoint.fromStand(Map<String, dynamic> stand) {
    final mac = normalizeMac(stand['esp_mac']?.toString() ?? '');
    final ssid = stand['esp_ssid']?.toString().trim() ?? '';
    final password = stand['esp_password']?.toString() ?? '';
    final host = stand['esp_ip']?.toString().trim() ?? '10.10.10.10';
    final port = (stand['esp_port'] as num?)?.toInt() ?? 80;
    if (mac.isEmpty || ssid.isEmpty || password.isEmpty || port < 1 || port > 65535) {
      throw const AppException('This stand is not configured for secure lock communication.');
    }
    return EspEndpoint(
      mac: mac,
      ssid: ssid,
      password: password,
      host: host,
      port: port,
    );
  }

  static String normalizeMac(String value) {
    final compact = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(compact)) return '';
    return List<String>.generate(
      6,
      (index) => compact.substring(index * 2, index * 2 + 2),
    ).join(':');
  }
}
