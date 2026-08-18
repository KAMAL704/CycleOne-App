import 'package:http/http.dart' as http;
import 'dart:convert';

class LockService {
  // Discover ESP on local network (simplified - use broadcast)
  static Future<String?> discoverESP(String macAddress) async {
    // In production, use mDNS or broadcast to find ESP
    // For now, assume ESP IP is known or use a lookup table
    final knownESP = {
      '00:1A:2B:3C:4D:60': '192.168.1.100', // Stand 1 - CSE Block
      '00:1A:2B:3C:4D:61': '192.168.1.101', // Stand 1 - CSE Block
      '00:1A:2B:3C:4D:62': '192.168.1.102', // Stand 1 - CSE Block
      // ... add all MAC addresses
    };
    return knownESP[macAddress];
  }

  static Future<bool> unlock(String macAddress) async {
    try {
      final ip = await discoverESP(macAddress);
      if (ip == null) return false;
      final url = Uri.http(ip, '/unlock');
      final response = await http.get(url);
      return response.statusCode == 200;
    } catch (e) {
      print('Unlock error: $e');
      return false;
    }
  }

  static Future<bool> lock(String macAddress) async {
    try {
      final ip = await discoverESP(macAddress);
      if (ip == null) return false;
      final url = Uri.http(ip, '/lock');
      final response = await http.get(url);
      return response.statusCode == 200;
    } catch (e) {
      print('Lock error: $e');
      return false;
    }
  }

  static Future<String?> getMACFromESP(String ip) async {
    try {
      final url = Uri.http(ip, '/mac');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['mac'];
      }
      return null;
    } catch (e) {
      print('Error getting MAC: $e');
      return null;
    }
  }
}