import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Details of a release that is newer than the installed application.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.apkUrl,
    required this.title,
    required this.notes,
    required this.mandatory,
  });

  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String apkUrl;
  final String title;
  final String notes;
  final bool mandatory;
}

class SettingsService {
  static const _updateKeys = <String>[
    'latest_version',
    'latest_build_number',
    'android_apk_url',
    'update_required',
    'update_title',
    'update_notes',
  ];

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

  /// Reads the public release settings and compares them with this APK.
  ///
  /// A missing setting or a temporary network error is treated as "no update"
  /// so an outage in the settings table cannot lock users out of the app.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final rows = await Supabase.instance.client
          .from('settings')
          .select('key,value')
          .inFilter('key', _updateKeys);
      final values = <String, String>{
        for (final row in (rows as List))
          if (row is Map && row['key'] != null)
            row['key'].toString(): row['value']?.toString() ?? '',
      };

      final latestVersion = values['latest_version']?.trim() ?? '';
      final latestBuild = int.tryParse(
            values['latest_build_number']?.trim() ?? '',
          ) ??
          0;
      if (latestVersion.isEmpty && latestBuild <= 0) return null;

      final package = await PackageInfo.fromPlatform();
      final currentVersion = package.version.trim();
      final currentBuild = int.tryParse(package.buildNumber.trim()) ?? 0;
      final newerVersion =
          _compareVersions(latestVersion, currentVersion) > 0;
      final newerBuild = latestBuild > 0 && currentBuild < latestBuild;
      if (!newerVersion && !newerBuild) return null;

      final url = values['android_apk_url']?.trim() ?? '';
      final required = (values['update_required'] ?? 'true').toLowerCase() !=
          'false';
      return AppUpdateInfo(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        latestVersion: latestVersion.isEmpty ? 'latest' : latestVersion,
        latestBuild: latestBuild,
        apkUrl: url,
        title: (values['update_title']?.trim().isNotEmpty ?? false)
            ? values['update_title']!.trim()
            : 'Update available',
        notes: values['update_notes']?.trim() ?? '',
        mandatory: required,
      );
    } catch (_) {
      return null;
    }
  }

  static int _compareVersions(String left, String right) {
    List<int> parse(String value) => value
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .take(3)
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

    final a = parse(left);
    final b = parse(right);
    for (var index = 0; index < 3; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
