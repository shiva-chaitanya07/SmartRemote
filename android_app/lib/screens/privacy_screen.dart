import 'package:flutter/material.dart';

import '../theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _paragraphs = <String>[
    'Phone Remote connects this Android app directly to a Windows computer that you choose on your local network. It does not require an account and the project does not include advertising or analytics SDKs.',
    'When you connect, the app sends the pairing code to that Windows computer over an encrypted TLS WebSocket. Keyboard input, text, mouse actions, and media commands that you choose to send are transmitted to that computer so it can perform those actions. The app developer does not receive this content.',
    'The app stores the laptop IP address, port, and the server certificate fingerprint on your phone so you can reconnect. The pairing code is not saved. Clearing the app storage removes these saved connection settings.',
    'The Windows companion stores its TLS certificate and private key in your Windows user LocalAppData folder. It keeps the pairing code in memory for the current run. It may show the connecting device IP and connection events in its console; it does not log typed text or key contents.',
    'The connection is intended for a trusted local Wi-Fi network. Before connecting, compare the certificate SHA-256 fingerprint shown by the Windows server with the fingerprint entered in the app. Do not share the pairing code. Stop the server when you are not using the remote.',
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
