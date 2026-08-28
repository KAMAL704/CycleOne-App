import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsService {
  static Future<bool> isMaintenanceMode() async {
    try {
      final response = await Supabase.instance.client
          .from('settings')
          .select('value')
          .eq('key', 'maintenance_mode')
          .maybeSingle();
      return response?['value'] == 'true';
    } catch (e) {
      // If error, assume no maintenance (app continues)
      return false;
    }
  }
}
