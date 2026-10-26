import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/remote_client.dart';

const _kHost = 'last_host';
const _kPort = 'last_port';

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

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      lastHost = prefs.getString(_kHost) ?? '';
      lastPort = prefs.getInt(_kPort) ?? 8765;
      if (mounted) {
        state = LinkSnapshot(
          status: state.status,
          host: lastHost,
          port: lastPort,
        );
      }
    } catch (_) {}
  }

  Future<void> connect(String host, int port) async {
    final cleaned = host.trim();
    if (cleaned.isEmpty) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        error: 'Enter the laptop IP address',
      );
      return;
    }
    if (InternetAddress.tryParse(cleaned) == null) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        error: 'Enter a valid IPv4 or IPv6 address',
      );
      return;
    }
    if (port < 1 || port > 65535) {
      state = LinkSnapshot(
        status: LinkStatus.disconnected,
        host: cleaned,
        port: port,
        error: 'Port must be between 1 and 65535',
      );
      return;
    }
    lastHost = cleaned;
    lastPort = port;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kHost, cleaned);
      await prefs.setInt(_kPort, port);
    } catch (_) {}
    await _client.connect(cleaned, port);
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
