import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/cycle_provider.dart';
import '../services/cycle_service.dart';
import '../services/esp_lock_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/stand_selector_bottom_sheet.dart';
import 'qr_scanner_screen.dart';

class CycleScreen extends StatefulWidget {
  const CycleScreen({super.key});

  @override
  State<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends State<CycleScreen> {
  bool _isProcessing = false;
  bool _isEspConnected = false;
  bool _isConnecting = false;

  // ============================================================
  // MAC -> CYCLE MAPPING
  // ============================================================

  final Map<String, String> _macToCycleMap = {
    '94B97E1A0FB5': 'CYCLE_1',
    '96B97E1A0FB5': 'CYCLE_3',
    'EEFABCC5617F': 'CYCLE_2',
  };

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<CycleProvider>().refreshCycle();
      _checkESPConnection();
    });
  }

  // ============================================================
  // CHECK ESP CONNECTION
  // ============================================================

  Future<void> _checkESPConnection() async {
    try {
      final connected = await ESPLockService.isConnectedToESP();

      if (!mounted) return;

      print('[CycleOne] 📡 ESP Connection Status: $connected');

      setState(() {
        _isEspConnected = connected;
      });
    } catch (e) {
      print('[CycleOne] ESP status error: $e');

      if (!mounted) return;

      setState(() {
        _isEspConnected = false;
      });
    }
  }

  // ============================================================
  // CONNECT ESP
  // ============================================================

  Future<bool> _connectToESP({String? mac}) async {
    if (_isConnecting) {
      print('[CycleOne] Connection skipped: already connecting');
      return false;
    }

    if (!mounted) return false;

    setState(() {
      _isConnecting = true;
    });

    bool connected = false;

    try {
      if (mac != null && mac.isNotEmpty) {
        print('[CycleOne] Connecting using MAC: $mac');
        connected = await ESPLockService.connectToESPWithNative(
          mac: mac,
        );
      } else {
        print('[CycleOne] Connecting using SSID');
        connected = await ESPLockService.connectToESP();
      }

      if (!mounted) return connected;

      print('[CycleOne] 📡 Connect result: $connected');

      setState(() {
        _isEspConnected = connected;
      });

      if (connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Connected to ESP Lock'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '❌ Failed to connect to ESP. Please check ESP power.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      return connected;
    } catch (e) {
      print('[CycleOne] ESP connection error: $e');

      if (!mounted) return false;

      setState(() {
        _isEspConnected = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ESP connection error: $e'),
          duration: Duration(seconds: 3),
        ),
      );

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  // ============================================================
  // EXTRACT MAC FROM QR
  // ============================================================

  String _extractMacFromQR(String qrData) {
    String mac = qrData.trim();

    if (mac.contains('cycleone://device/')) {
      mac = mac.split('/').last;
    }

    mac = mac
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toUpperCase();

    if (RegExp(r'^[0-9A-F]{12}$').hasMatch(mac)) {
      return mac;
    }

    return '';
  }

  // ============================================================
  // CYCLE ID -> MAC
  // ============================================================

  String? _cycleIdToMac(String cycleId) {
    for (final entry in _macToCycleMap.entries) {
      if (entry.value == cycleId) {
        return entry.key;
      }
    }
    return null;
  }

  // ============================================================
  // START RIDE FROM STAND
  // ============================================================

  Future<void> _startRideFromStand(BuildContext context) async {
    if (_isProcessing) return;

    final provider = context.read<CycleProvider>();

    if (provider.hasCycle) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have an active ride! End it first.'),
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final result = await showStandSelectorBottomSheet(
        context,
        forReturn: false,
      );

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final cycleId = result['cycleId']?.toString();
      final standId = result['standId']?.toString();

      if (cycleId == null || cycleId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid cycle selected!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      if (standId == null || standId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid stand selected!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final activeRide = await CycleService.getActiveRide();

      if (!mounted) return;

      if (activeRide != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have an active ride!'),
          ),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      if (!_isEspConnected) {
        final connected = await _connectToESP();

        if (!mounted) return;

        if (!connected) {
          setState(() {
            _isProcessing = false;
          });
          return;
        }
      }

      final ride = await CycleService.startRideFromStand(
        standId,
        cycleId,
      );

      if (!mounted) return;

      if (ride != null) {
        provider.allocateCycle(
          cycleId,
          ride['id'],
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ride started! Cycle $cycleId unlocked.'),
          ),
        );

        await provider.refreshCycle();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start ride.')),
        );
      }
    } catch (e) {
      print('[CycleOne] Error in start ride: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ============================================================
  // SCAN TO UNLOCK
  // ============================================================

  Future<void> _scanToUnlock(BuildContext context) async {
    if (_isProcessing) return;

    final provider = context.read<CycleProvider>();

    if (provider.hasCycle) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have an active ride! End it first.'),
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final scannedValue = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const QrScannerScreen(),
        ),
      );

      if (!mounted) return;

      if (scannedValue == null || scannedValue.isEmpty) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final String mac = _extractMacFromQR(scannedValue);

      print('[CycleOne] 📱 Extracted MAC: $mac');

      if (mac.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final String cycleId = _macToCycleMap[mac] ?? '';

      print('[CycleOne] 📱 Cycle ID: $cycleId');

      if (cycleId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cycle not found!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      Map<String, dynamic>? cycleData;

      try {
        cycleData = await Supabase.instance.client
            .from('cycles')
            .select('stand_id, status')
            .eq('id', cycleId)
            .maybeSingle()
            .timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        print('[CycleOne] Database error: $e');

        cycleData = {
          'stand_id': 'stand_1',
          'status': 'available',
        };
      }

      if (!mounted) return;

      if (cycleData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cycle not found in database!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      if (cycleData['status'] != 'available') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cycle is not available!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final activeRide = await CycleService.getActiveRide();

      if (!mounted) return;

      if (activeRide != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have an active ride!'),
          ),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      if (!_isEspConnected) {
        final connected = await _connectToESP(mac: mac);

        if (!mounted) return;

        if (!connected) {
          setState(() {
            _isProcessing = false;
          });
          return;
        }
      }

      print('[CycleOne] 🔓 Unlocking cycle: $cycleId');

      final unlockSuccess = await ESPLockService.unlockNative(mac);

      if (!mounted) return;

      if (!unlockSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to unlock ESP. Please check connection.'),
          ),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      print('[CycleOne] ✅ Unlock successful');

      final ride = await CycleService.startRideFromStand(
        cycleData['stand_id'],
        cycleId,
      );

      if (!mounted) return;

      if (ride != null) {
        provider.allocateCycle(
          cycleId,
          ride['id'],
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ride started! Cycle $cycleId unlocked.'),
          ),
        );

        await provider.refreshCycle();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start ride.')),
        );
      }
    } catch (e) {
      print('[CycleOne] ❌ Error in scan unlock: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

// ============================================================
// RETURN RIDE AT STAND - COMPLETE FIX ✅
// ============================================================

  Future<void> _returnRideAtStand(BuildContext context) async {
    if (_isProcessing) return;

    final provider = context.read<CycleProvider>();

    final currentCycleId = provider.currentCycleId;
    final currentRideId = provider.currentRideId;

    if (currentCycleId == null || currentRideId == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active ride to return!')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final String? mac = _cycleIdToMac(currentCycleId);

      if (mac == null || mac.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cycle MAC not found!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final result = await showStandSelectorBottomSheet(
        context,
        forReturn: true,
      );

      if (!mounted) return;

      if (result == null) {
        print('[CycleOne] Return cancelled');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final returnStandId = result['standId']?.toString();

      if (returnStandId == null || returnStandId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid return stand!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      print('[CycleOne] 📍 Return stand: $returnStandId');

      print('[CycleOne] 🔒 Starting lock sequence');
      print('[CycleOne] 📡 MAC: $mac');

      final lockSuccess = await ESPLockService.lockNative(mac);

      if (!mounted) return;

      if (!lockSuccess) {
        print('[CycleOne] ❌ ESP lock failed');

        setState(() {
          _isEspConnected = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to lock cycle. Keep the phone near the cycle and try again.',
            ),
          ),
        );

        setState(() {
          _isProcessing = false;
        });
        return;
      }

      print('[CycleOne] ✅ ESP LOCK SUCCESS');

      print('[CycleOne] 💾 Updating ride database...');

      final success = await CycleService.endRideAtStand(
        currentRideId,
        currentCycleId,
        returnStandId,
      );

      if (!mounted) return;

      if (success) {
        provider.returnCycle();

        if (!mounted) return;

        setState(() {
          _isEspConnected = false;
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ride ended successfully! Cycle returned.'),
            duration: Duration(seconds: 3),
          ),
        );

        print('[CycleOne] =================================');
        print('[CycleOne] ✅ RETURN COMPLETE');
        print('[CycleOne] 🚲 Cycle: $currentCycleId');
        print('[CycleOne] 📍 Stand: $returnStandId');
        print('[CycleOne] =================================');

        // ✅ Refresh provider
        await provider.refreshCycle();

        if (!mounted) return;

        setState(() {});

        // ✅ FIXED: Wait and navigate properly
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              // ✅ Use pushReplacementNamed instead of pop
              Navigator.pushReplacementNamed(
                context,
                '/home', // Your home route name
              );
            }
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cycle locked, but ride update failed. Please contact admin.',
            ),
          ),
        );
      }
    } catch (e) {
      print('[CycleOne] ❌ Error in return ride: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Return error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

// ============================================================
// SCAN TO RETURN - COMPLETE FIX ✅
// ============================================================

  Future<void> _scanToReturn(BuildContext context) async {
    if (_isProcessing) return;

    final provider = context.read<CycleProvider>();

    final currentCycleId = provider.currentCycleId;
    final currentRideId = provider.currentRideId;

    if (currentCycleId == null || currentRideId == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active ride to return!')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      print('[CycleOne] =================================');
      print('[CycleOne] 📱 RETURN QR SCAN START');

      final scannedValue = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const QrScannerScreen(),
        ),
      );

      if (!mounted) return;

      if (scannedValue == null || scannedValue.isEmpty) {
        print('[CycleOne] ❌ No QR value');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      print('[CycleOne] 📱 QR Value: $scannedValue');

      final String mac = _extractMacFromQR(scannedValue);

      print('[CycleOne] 📡 Extracted MAC: $mac');

      if (mac.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid cycle QR code!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final String scannedCycleId = _macToCycleMap[mac] ?? '';

      print('[CycleOne] 🚲 Scanned Cycle: $scannedCycleId');
      print('[CycleOne] 🚲 Current Cycle: $currentCycleId');

      if (scannedCycleId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cycle not found!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      if (scannedCycleId != currentCycleId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid return. You are riding $currentCycleId'),
          ),
        );
        print('[CycleOne] ❌ Wrong cycle scanned');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      print('[CycleOne] ✅ Correct cycle scanned');

      final result = await showStandSelectorBottomSheet(
        context,
        forReturn: true,
      );

      if (!mounted) return;

      if (result == null) {
        print('[CycleOne] ℹ️ Return cancelled');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final returnStandId = result['standId']?.toString();

      if (returnStandId == null || returnStandId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid return stand!')),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      print('[CycleOne] 📍 Selected stand: $returnStandId');

      print('[CycleOne] =================================');
      print('[CycleOne] 🔒 STARTING ESP LOCK');
      print('[CycleOne] 📡 MAC: $mac');

      final lockSuccess = await ESPLockService.lockNative(mac);

      if (!mounted) return;

      if (!lockSuccess) {
        print('[CycleOne] ❌ ESP LOCK FAILED');

        setState(() {
          _isEspConnected = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to lock cycle. Keep the phone near the cycle and try again.',
            ),
          ),
        );

        setState(() {
          _isProcessing = false;
        });
        return;
      }

      print('[CycleOne] ✅ ESP LOCK SUCCESS');

      print('[CycleOne] 💾 Ending ride...');

      final success = await CycleService.endRideAtStand(
        currentRideId,
        currentCycleId,
        returnStandId,
      );

      if (!mounted) return;

      if (success) {
        provider.returnCycle();

        if (!mounted) return;

        setState(() {
          _isEspConnected = false;
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ride ended successfully! Cycle returned.'),
            duration: Duration(seconds: 3),
          ),
        );

        print('[CycleOne] =================================');
        print('[CycleOne] ✅ RETURN COMPLETE');
        print('[CycleOne] 🚲 Cycle: $currentCycleId');
        print('[CycleOne] 📍 Stand: $returnStandId');
        print('[CycleOne] =================================');

        // ✅ Refresh provider
        await provider.refreshCycle();

        if (!mounted) return;

        setState(() {});

        // ✅ FIXED: Wait and navigate properly
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              // ✅ Use pushReplacementNamed instead of pop
              Navigator.pushReplacementNamed(
                context,
                '/home', // Your home route name
              );
            }
          });
        }
      } else {
        print('[CycleOne] ⚠️ ESP locked but database update failed');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cycle locked, but ride update failed. Please contact admin.',
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('[CycleOne] =================================');
      print('[CycleOne] ❌ ERROR IN SCAN RETURN');
      print('[CycleOne] ❌ $e');
      print('[CycleOne] ❌ $stackTrace');
      print('[CycleOne] =================================');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Return error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  // ============================================================
  // UNLOCK OPTIONS
  // ============================================================

  void _showUnlockOptions(BuildContext context) {
    final provider = context.read<CycleProvider>();

    if (provider.hasCycle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have an active ride! End it first.'),
        ),
      );
      return;
    }

    if (_isProcessing || _isConnecting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait, processing...')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner, color: Colors.green),
              title: const Text('Scan QR Code'),
              subtitle: const Text('Use camera or gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _scanToUnlock(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.storefront, color: Colors.green),
              title: const Text('Select from Stands'),
              subtitle: const Text('Choose a stand to ride'),
              onTap: () {
                Navigator.pop(sheetContext);
                _startRideFromStand(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // RETURN OPTIONS
  // ============================================================

  void _showReturnOptions(BuildContext context) {
    final provider = context.read<CycleProvider>();

    if (!provider.hasCycle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active ride to return!')),
      );
      return;
    }

    if (_isProcessing || _isConnecting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait, processing...')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner, color: Colors.red),
              title: const Text('Scan QR Code to Return'),
              subtitle: const Text('Use camera or gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _scanToReturn(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.storefront, color: Colors.red),
              title: const Text('Select Stand to Return'),
              subtitle: const Text('Choose any stand to return cycle'),
              onTap: () {
                Navigator.pop(sheetContext);
                _returnRideAtStand(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<CycleProvider>().reset();
              Navigator.pop(dialogContext);

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged out successfully')),
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CycleProvider>();

    final hasCycle = provider.hasCycle;
    final cycleId = provider.currentCycleId ?? '';
    final isLoading = provider.isLoading;

    print('[CycleOne] Build - _isEspConnected: $_isEspConnected, hasCycle: $hasCycle');

    return Scaffold(
      appBar: AppBar(
        title: const Text('CycleOne'),
        actions: [
          IconButton(
            icon: Icon(
              _isEspConnected ? Icons.wifi : Icons.wifi_off,
              color: _isEspConnected ? Colors.green : Colors.red,
            ),
            onPressed: _isProcessing || _isConnecting ? null : () async {
              final connected = await _connectToESP();
              if (connected) {
                await _checkESPConnection();
              }
            },
            tooltip: _isEspConnected ? 'ESP Connected' : 'ESP Disconnected',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Center(
              child: Text(
                'CONNECT - COMMUTE - CONSERVE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      hasCycle ? Icons.electric_bike : Icons.pedal_bike,
                      size: 60,
                      color: hasCycle ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasCycle ? 'Ride in Progress' : 'No active ride',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (hasCycle) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'Cycle: $cycleId',
                          style: TextStyle(
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Return to any stand',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CustomButton(
                        text: 'End Ride',
                        icon: Icons.qr_code_scanner,
                        color: Colors.red,
                        onPressed: () {
                          if (_isProcessing || _isConnecting) return;
                          _showReturnOptions(context);
                        },
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'No active ride',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: (_isProcessing || _isConnecting)
                            ? null
                            : () => _showUnlockOptions(context),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Start a Ride'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ],
                    if (hasCycle)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Return using the same method you started (scan or stand)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        'https://upload.wikimedia.org/wikipedia/en/4/4f/NHPC_logo.png',
                        height: 40,
                        errorBuilder: (_, __, ___) =>
                        const Text('NHPC', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Sponsored by NHPC',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'SLIET',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Thanking Dr. Amit Kansal',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}