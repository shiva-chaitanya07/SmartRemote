import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bluetooth_hid_client.dart';
import '../theme.dart';
import 'bluetooth_remote_screen.dart';

class BluetoothConnectScreen extends StatefulWidget {
  const BluetoothConnectScreen({super.key});

  @override
  State<BluetoothConnectScreen> createState() => _BluetoothConnectScreenState();
}

class _BluetoothConnectScreenState extends State<BluetoothConnectScreen> {
  final _client = BluetoothHidClient();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  List<BluetoothHost> _hosts = [];
  bool _supported = false;
  bool _starting = false;
  bool _connecting = false;
  int _connectAttempt = 0;
  String _state = 'Not started';
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSupport();
    _subscription = _client.events.listen(_onEvent);
    _resumeRememberedHost();
  }

  Future<void> _resumeRememberedHost() async {
    try {
      final address = await _client.lastHostAddress();
      if (mounted && address != null) await _start();
    } catch (_) {
      // Keep manual setup available if reading the saved device fails.
    }
  }

  Future<void> _checkSupport() async {
    try {
      final supported = await _client.isSupported;
      if (mounted) setState(() => _supported = supported);
    } on PlatformException catch (e) {
      if (mounted)
        setState(() => _error = e.message ?? 'Bluetooth check failed.');
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    if (event['type'] == 'ready') {
      final ready = event['value'] == true;
      setState(() => _state =
          ready ? 'HID ready — pair with Windows' : 'HID is not registered');
    } else if (event['type'] == 'connection') {
      final state = event['value']?.toString() ?? 'disconnected';
      setState(() {
        _state = state;
        if (state == 'connected' || state == 'disconnected')
          _connecting = false;
      });
      if (state == 'connected') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => BluetoothRemoteScreen(client: _client)),
        );
      }
    } else if (event['type'] == 'error') {
      setState(() => _error = event['value']?.toString());
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _client.start();
      await _refresh();
      final rememberedAddress = await _client.lastHostAddress();
      final rememberedHost =
          _hosts.where((host) => host.address == rememberedAddress).firstOrNull;
      if (rememberedHost != null && mounted) {
        await _connect(rememberedHost);
      } else if (mounted) {
        setState(() => _state = 'Ready to pair');
      }
    } on PlatformException catch (e) {
      if (mounted)
        setState(() => _error = e.message ?? 'Could not start Bluetooth mode.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final hosts = await _client.bondedHosts();
      if (mounted) setState(() => _hosts = hosts);
    } on PlatformException catch (e) {
      if (mounted)
        setState(() => _error = e.message ?? 'Could not read paired devices.');
    }
  }

  Future<void> _connect(BluetoothHost host) async {
    await _client.rememberHost(host.address);
    setState(() {
      _error = null;
      _connecting = true;
      _state = 'Requesting HID connection…';
    });
    final attempt = ++_connectAttempt;
    try {
      await _client.connect(host.address);
      if (!mounted || attempt != _connectAttempt) {
        return;
      }
      setState(() => _state = 'Connecting to ${host.name}…');
      Future<void>.delayed(const Duration(seconds: 12), () {
        if (!mounted || attempt != _connectAttempt || !_connecting) {
          return;
        }
        setState(() {
          _connecting = false;
          _state = 'Not connected';
          _error =
              'Windows pairing and the HID link are separate. If Android says the laptop is already paired but HID was rejected, tap Enable Bluetooth pairing again. If that still fails, remove Phone Remote from Windows Bluetooth settings, forget the laptop on the phone, then enable HID before pairing again.';
        });
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = e.message ??
              'Android could not start the Bluetooth HID connection.';
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth remote')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 22),
            const Text('Use your phone as a Bluetooth keyboard',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Bluetooth HID mode sends standard keyboard and mouse input directly to Windows. It does not need the Windows Phone Remote server.',
              style: TextStyle(color: AppTheme.textMuted, height: 1.45),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16)),
              child: Text('Status: $_state',
                  style: const TextStyle(color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 16),
            if (!_supported)
              const Text(
                'This phone may not expose Android Bluetooth HID. Try the Wi-Fi mode if Bluetooth is unavailable.',
                style: TextStyle(color: AppTheme.disconnected),
              ),
            ElevatedButton.icon(
              onPressed: !_supported || _starting ? null : _start,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_starting ? 'Starting…' : 'Enable Bluetooth pairing'),
            ),
            const SizedBox(height: 12),
            const Text(
              'After enabling, pair from Windows Bluetooth Settings once. Phone Remote remembers that laptop and reconnects it when you enable Bluetooth again. You do not need to unpair either device.',
              style: TextStyle(color: AppTheme.textMuted, height: 1.45),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh paired devices'),
            ),
            ..._hosts.map((host) => Card(
                  color: AppTheme.surface,
                  child: ListTile(
                    leading: const Icon(Icons.laptop_windows,
                        color: AppTheme.accentSoft),
                    title: Text(host.name),
                    subtitle: Text(host.address),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _connect(host),
                  ),
                )),
            if (_hosts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'No paired devices found yet. Pair the phone from Windows Bluetooth Settings first.',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppTheme.disconnected)),
            ],
            const SizedBox(height: 18),
            const Text(
              'Android disconnects Bluetooth HID when Phone Remote is fully closed or moved out of the foreground. Reopen Bluetooth remote and tap Enable Bluetooth pairing to reconnect to the remembered laptop; the pairing remains saved.',
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
