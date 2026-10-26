import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../services/remote_client.dart';
import '../theme.dart';
import '../widgets/status_banner.dart';
import 'remote_screen.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8765');
  bool _hydrated = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _hydrate(LinkSnapshot snapshot) {
    if (_hydrated) return;
    if (snapshot.host.isEmpty) return;
    _ipController.text = snapshot.host;
    _portController.text = '${snapshot.port}';
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
    await ref.read(connectionProvider.notifier).connect(ip, port);
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBanner(snapshot: snapshot),
              ),
              const Spacer(),
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
                'Turn this phone into a wireless keyboard and touchpad for your Windows laptop.',
                style: TextStyle(color: AppTheme.textMuted, height: 1.4),
              ),
              const SizedBox(height: 28),
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
              const Spacer(flex: 2),
              const Text(
                'Phone and laptop must be on the same Wi-Fi. The Python server prints the IP when it starts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
