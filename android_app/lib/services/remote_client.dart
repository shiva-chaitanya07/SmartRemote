import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol.dart';

enum LinkStatus { disconnected, connecting, connected, reconnecting }

class LinkSnapshot {
  const LinkSnapshot({
    required this.status,
    this.host = '',
    this.port = 8765,
    this.error,
  });

  final LinkStatus status;
  final String host;
  final int port;
  final String? error;

  bool get isConnected => status == LinkStatus.connected;

  String get label {
    switch (status) {
      case LinkStatus.connected:
        return 'Connected';
      case LinkStatus.connecting:
        return 'Connecting…';
      case LinkStatus.reconnecting:
        return 'Reconnecting…';
      case LinkStatus.disconnected:
        return 'Disconnected';
    }
  }
}

/// Owns the WebSocket, keepalive pings, and auto-reconnect.
class RemoteClient {
  RemoteClient({this.onState});

  final void Function(LinkSnapshot state)? onState;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _wantConnected = false;
  int _attempt = 0;
  String _host = '';
  int _port = 8765;
  LinkStatus _status = LinkStatus.disconnected;

  LinkSnapshot get snapshot => LinkSnapshot(
        status: _status,
        host: _host,
        port: _port,
      );

  Future<void> connect(String host, int port) async {
    _host = host.trim();
    _port = port;
    _wantConnected = true;
    _attempt = 0;
    if (_host.isEmpty || _port < 1 || _port > 65535) {
      _set(LinkStatus.disconnected, error: 'Enter a valid IP address and port');
      return;
    }
    await _open(isRetry: false);
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _tearDown();
    _set(LinkStatus.disconnected);
  }

  void send(String json) {
    if (_status != LinkStatus.connected) return;
    try {
      _channel?.sink.add(json);
    } catch (_) {
      _scheduleReconnect('Send failed');
    }
  }

  Future<void> dispose() async {
    await disconnect();
  }

  Future<void> _open({required bool isRetry}) async {
    _reconnectTimer?.cancel();
    await _tearDown();
    _set(isRetry ? LinkStatus.reconnecting : LinkStatus.connecting);

    final uri = Uri(scheme: 'ws', host: _host, port: _port);
    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        connectTimeout: const Duration(seconds: 6),
      );
      _channel = channel;
      await channel.ready;
      _attempt = 0;
      _set(LinkStatus.connected);
      _startPing();
      _sub = channel.stream.listen(
        _onData,
        onError: (Object error) => _scheduleReconnect(error.toString()),
        onDone: () => _scheduleReconnect('Connection closed'),
        cancelOnError: true,
      );
    } on WebSocketChannelException catch (error) {
      _scheduleReconnect(error.message ?? 'WebSocket error');
    } catch (error) {
      _scheduleReconnect(error.toString());
    }
  }

  void _onData(dynamic raw) {
    final message = ServerMessage.tryParse(raw);
    if (message == null) return;
    if (message.type == 'hello' && message.status == 'ok') {
      _set(LinkStatus.connected);
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      send(RemoteEvent.ping());
    });
  }

  void _scheduleReconnect(String reason) {
    _tearDown();
    if (!_wantConnected) {
      _set(LinkStatus.disconnected, error: reason);
      return;
    }
    _attempt += 1;
    final waitMs = (500 * (1 << (_attempt.clamp(0, 4)))).clamp(500, 8000);
    _set(LinkStatus.reconnecting, error: reason);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: waitMs), () {
      if (_wantConnected) {
        _open(isRetry: true);
      }
    });
  }

  Future<void> _tearDown() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _set(LinkStatus status, {String? error}) {
    _status = status;
    onState?.call(
      LinkSnapshot(
        status: status,
        host: _host,
        port: _port,
        error: error,
      ),
    );
  }
}
