import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../services/remote_client.dart';
import '../theme.dart';
import '../widgets/status_banner.dart';
import 'privacy_screen.dart';
import 'bluetooth_connect_screen.dart';
import 'remote_screen.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8765');
  final _fingerprintController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  bool _hydrated = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _fingerprintController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  void _hydrate(LinkSnapshot snapshot) {
    if (_hydrated) return;
    if (snapshot.host.isEmpty) return;
    _ipController.text = snapshot.host;
    _portController.text = '${snapshot.port}';
    _fingerprintController.text = snapshot.certificateFingerprint;
    _hydrated = true;
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter the laptop IP shown by the server')),
      );
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port must be between 1 and 65535')),
      );
      return;
    }
    await ref.read(connectionProvider.notifier).connect(
          ip,
          port,
          _fingerprintController.text,
          _pairingCodeController.text,
        );
  }

  Future<void> _cancelRetry() =>
      ref.read(connectionProvider.notifier).disconnect();

  @override
  Widget build(BuildContext context) {
    ref.listen<LinkSnapshot>(connectionProvider, (prev, next) {
      if (next.status == LinkStatus.connected &&
          prev?.status != LinkStatus.connected) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RemoteScreen()),
        );
      }
    });

    final snapshot = ref.watch(connectionProvider);
    _hydrate(snapshot);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBanner(snapshot: snapshot),
              ),
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.phonelink_rounded,
                    color: AppTheme.accent, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Phone Remote',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Control your Windows laptop securely over your local Wi-Fi.',
                style: TextStyle(color: AppTheme.textMuted, height: 1.4),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BluetoothConnectScreen()),
                ),
                icon: const Icon(Icons.bluetooth),
                label: const Text('Try Bluetooth HID (experimental)'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bluetooth HID can control Windows directly without the laptop server. Availability depends on your phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Laptop IP address',
                  hintText: '192.168.1.20',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '8765',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pairingCodeController,
                keyboardType: TextInputType.number,
                maxLength: 8,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: '8-digit pairing code',
                  hintText: 'Shown in the Windows server window',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fingerprintController,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                minLines: 2,
                maxLines: 2,
                maxLength: 95,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  labelText: 'Server certificate SHA-256 fingerprint',
                  hintText: 'Paste the fingerprint shown by the server',
                  counterText: '',
                ),
              ),
              if (snapshot.error != null &&
                  snapshot.status != LinkStatus.connected) ...[
                const SizedBox(height: 12),
                Text(
                  snapshot.error!,
                  style: const TextStyle(color: AppTheme.disconnected),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: snapshot.status == LinkStatus.connecting
                    ? null
                    : snapshot.status == LinkStatus.reconnecting
                        ? _cancelRetry
                        : _connect,
                child: Text(
                  snapshot.status == LinkStatus.connecting
                      ? 'Connecting…'
                      : snapshot.status == LinkStatus.reconnecting
                          ? 'Cancel retry'
                          : 'Connect',
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Copy the pairing code and certificate fingerprint from the Windows server. Compare the fingerprint before connecting. Both devices must be on the same trusted Wi-Fi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 12, height: 1.4),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                ),
                child: const Text('Privacy Policy'),
              ),
              const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
