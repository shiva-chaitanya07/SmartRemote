import 'package:flutter/material.dart';

import '../theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _paragraphs = <String>[
    'Phone Remote connects this Android app directly to a Windows computer that you choose, using either local Wi-Fi with the Windows companion or experimental Bluetooth HID mode when supported. It does not require an account and the project does not include advertising or analytics SDKs.',
    'In Wi-Fi mode, the app sends the pairing code and your chosen keyboard, text, mouse, and media events to the Windows companion over an encrypted TLS WebSocket. In Bluetooth HID mode, selected input events are sent directly to the paired Windows computer using Bluetooth HID reports. The app developer does not receive these events.',
    'The app stores the Wi-Fi laptop IP address, port, and server certificate fingerprint on your phone so you can reconnect. The pairing code is not saved. Android manages Bluetooth pairing; the app reads paired device names and addresses to let you select a device, and saves only the selected device address locally so it can reconnect. It does not save the full paired-device list. Clearing app storage removes the saved Wi-Fi and Bluetooth selection settings.',
    'The Windows companion stores its TLS certificate and private key in your Windows user LocalAppData folder. It keeps the pairing code in memory for the current run. It may show the connecting device IP and connection events in its console; it does not log typed text or key contents.',
    'Wi-Fi mode is intended for a trusted local network. Compare the Windows server certificate fingerprint before connecting and keep the pairing code private. Bluetooth mode relies on Android and Windows Bluetooth pairing; keep Phone Remote in the foreground while controlling the laptop. Stop the Wi-Fi server when you are not using it.',
    'No data is sent to a Phone Remote developer server. The app does not intentionally collect analytics or track users. Google Play Data safety declarations must still be completed based on the final app behavior and Google Play definitions.',
    'Retention and deletion: saved connection settings remain on your phone until you clear app storage or uninstall the app. The Windows certificate and private key remain in your Windows user profile until you remove the Phone Remote folder from LocalAppData. Keyboard and mouse event contents are not retained by the companion.',
    'Publisher: REPLACE THIS PLACEHOLDER WITH THE LEGAL OR DEVELOPER NAME USED IN PLAY CONSOLE.',
    'Privacy contact: REPLACE THIS PLACEHOLDER WITH A MONITORED CONTACT EMAIL BEFORE PUBLICATION.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          const Text(
            'Phone Remote · Effective October 26, 2026',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          for (final paragraph in _paragraphs) ...[
            Text(
              paragraph,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                height: 1.55,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
