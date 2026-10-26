import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/remote_client.dart';
import '../utils/network_address.dart';

const _kHost = 'last_host';
const _kPort = 'last_port';
const _kFingerprint = 'server_certificate_fingerprint';

class ConnectionController extends StateNotifier<LinkSnapshot> {
  ConnectionController()
      : super(const LinkSnapshot(status: LinkStatus.disconnected)) {
    _client = RemoteClient(onState: (next) {
      if (mounted) state = next;
    });
    _restore();
  }

  late final RemoteClient _client;
  String lastHost = '';
  int lastPort = 8765;
  String lastFingerprint = '';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      lastHost = prefs.getString(_kHost) ?? '';
      lastPort = prefs.getInt(_kPort) ?? 8765;
      lastFingerprint = prefs.getString(_kFingerprint) ?? '';
      if (mounted) {
        state = LinkSnapshot(
          status: state.status,
          host: lastHost,
          port: lastPort,
          certificateFingerprint: lastFingerprint,
        );
      }
    } catch (_) {}
  }

  Future<void> connect(
    String host,
    int port,
    String fingerprint,
    String pairingCode,
  ) async {
    final cleaned = host.trim();
    final normalizedFingerprint =
        fingerprint.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
    if (cleaned.isEmpty) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        certificateFingerprint: normalizedFingerprint,
        error: 'Enter the laptop IP address',
      );
      return;
    }
    if (!isLocalNetworkAddress(cleaned)) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        certificateFingerprint: normalizedFingerprint,
        error: 'Enter a private LAN IPv4 or IPv6 address',
      );
      return;
    }
    if (port < 1 || port > 65535) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        certificateFingerprint: normalizedFingerprint,
        error: 'Port must be between 1 and 65535',
      );
      return;
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedFingerprint)) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        certificateFingerprint: normalizedFingerprint,
        error: 'Enter the server SHA-256 fingerprint (64 hex digits)',
      );
      return;
    }
    final code = pairingCode.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        certificateFingerprint: normalizedFingerprint,
        error: 'Enter the 8-digit pairing code printed by the server',
      );
      return;
    }
    lastHost = cleaned;
    lastPort = port;
    lastFingerprint = normalizedFingerprint;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kHost, cleaned);
      await prefs.setInt(_kPort, port);
      await prefs.setString(_kFingerprint, normalizedFingerprint);
    } catch (_) {}
    await _client.connect(cleaned, port, normalizedFingerprint, code);
  }

  Future<void> disconnect() => _client.disconnect();

  void send(String json) => _client.send(json);

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionController, LinkSnapshot>(
  (ref) => ConnectionController(),
);
