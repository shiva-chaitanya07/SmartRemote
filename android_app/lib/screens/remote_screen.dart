import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../theme.dart';
import '../widgets/media_bar.dart';
import '../widgets/status_banner.dart';
import '../widgets/touchpad.dart';
import '../widgets/virtual_keyboard.dart';
import 'connect_screen.dart';

class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(connectionProvider);
    final controller = ref.read(connectionProvider.notifier);
    final live = snapshot.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Phone Remote'),
            Text(
              snapshot.host.isEmpty ? '' : '${snapshot.host}:${snapshot.port}',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: StatusBanner(snapshot: snapshot)),
          ),
          IconButton(
            tooltip: 'Disconnect',
            onPressed: () async {
              await controller.disconnect();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ConnectScreen()),
                );
              }
            },
            icon: const Icon(Icons.link_off_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              if (!live)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    snapshot.error ?? 'Trying to reach the laptop…',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
              Expanded(
                child: Touchpad(enabled: live, onSend: controller.send),
              ),
              const SizedBox(height: 10),
              ClickBar(enabled: live, onSend: controller.send),
              const SizedBox(height: 10),
              MediaBar(enabled: live, onSend: controller.send),
              const SizedBox(height: 12),
              VirtualKeyboard(enabled: live, onSend: controller.send),
            ],
          ),
        ),
      ),
    );
  }
}
