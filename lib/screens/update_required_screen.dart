import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key});

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  AppUpdateInfo? _info;
  bool _checking = false;
  bool _opening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _info ??= ModalRoute.of(context)?.settings.arguments as AppUpdateInfo?;
  }

  Future<void> _openUpdate() async {
    final info = _info;
    if (info == null || info.apkUrl.isEmpty) {
      _showMessage('APK download link is not configured yet. Please contact admin.');
      return;
    }
    final uri = Uri.tryParse(info.apkUrl);
    if (uri == null || !uri.hasScheme) {
      _showMessage('The APK download link is invalid. Please contact admin.');
      return;
    }
    setState(() => _opening = true);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) setState(() => _opening = false);
    if (!opened && mounted) {
      _showMessage('Could not open the download link. Try again.');
    }
  }

  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    final update = await SettingsService.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _info = update;
    });
    if (update == null || !update.mandatory) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.system_update_rounded,
                        size: 78,
                        color: Color(0xFF167A4A),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        info?.title ?? 'Update available',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        info == null
                            ? 'A new CycleOne version is required before you can continue.'
                            : 'Please install version ${info.latestVersion} to continue using CycleOne.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      if (info?.notes.isNotEmpty ?? false) ...[
                        const SizedBox(height: 14),
                        Text(
                          info!.notes,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (info != null)
                        Text(
                          'Installed: ${info.currentVersion} (${info.currentBuild})\n'
                          'New version: ${info.latestVersion} (${info.latestBuild})',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _opening ? null : _openUpdate,
                          icon: _opening
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download_rounded),
                          label: const Text('Download update'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _checking ? null : _checkAgain,
                        icon: _checking
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: const Text('I have installed it — check again'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'After downloading, tap Install. Reopen CycleOne after installation.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
