import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bluetooth_hid_client.dart';
import '../theme.dart';
import '../widgets/media_bar.dart';
import '../widgets/touchpad.dart';
import '../widgets/virtual_keyboard.dart';
import 'bluetooth_connect_screen.dart';

class BluetoothRemoteScreen extends StatefulWidget {
  const BluetoothRemoteScreen({super.key, required this.client});
  final BluetoothHidClient client;

  @override
  State<BluetoothRemoteScreen> createState() => _BluetoothRemoteScreenState();
}

class _BluetoothRemoteScreenState extends State<BluetoothRemoteScreen> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _connected = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.client.events.listen((event) {
      if (!mounted) return;
      if (event['type'] == 'connection') {
        setState(() {
          _connected = event['value'] == 'connected';
          if (!_connected) _error = 'Bluetooth disconnected. Reconnect from the Bluetooth screen.';
        });
      }
    });
  }

  Future<void> _send(String json) async {
    try {
      final sent = await widget.client.send(json);
      if (!sent && mounted) setState(() => _error = 'Could not send input. Check the Bluetooth connection.');
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Bluetooth input failed.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Invalid remote input.');
    }
  }

  Future<void> _disconnect() async {
    try { await widget.client.disconnect(); } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const BluetoothConnectScreen()),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Remote · Bluetooth'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(_connected ? 'Connected' : 'Disconnected',
                  style: TextStyle(color: _connected ? AppTheme.connected : AppTheme.disconnected)),
            ),
          ),
          IconButton(onPressed: _disconnect, tooltip: 'Disconnect', icon: const Icon(Icons.link_off_rounded)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.disconnected, fontSize: 12)),
                ),
              Expanded(child: Touchpad(enabled: _connected, onSend: _send)),
              const SizedBox(height: 10),
              ClickBar(enabled: _connected, onSend: _send),
              const SizedBox(height: 10),
              MediaBar(enabled: _connected, onSend: _send),
              const SizedBox(height: 12),
              VirtualKeyboard(enabled: _connected, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}
