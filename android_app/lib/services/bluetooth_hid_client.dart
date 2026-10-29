import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothHidClient {
  static const _methods = MethodChannel('phone_remote/bluetooth_hid');
  static const _events = EventChannel('phone_remote/bluetooth_hid_events');
  static const _lastHostKey = 'bluetooth_hid_last_host';

  Stream<Map<String, dynamic>> get events =>
      _events.receiveBroadcastStream().where((value) => value is Map).map(
            (value) => Map<String, dynamic>.from(value as Map),
          );

  Future<bool> get isSupported async =>
      await _methods.invokeMethod<bool>('isSupported') ?? false;

  Future<void> start() async {
    await _methods.invokeMethod<bool>('start');
  }

  Future<List<BluetoothHost>> bondedHosts() async {
    final rows = await _methods.invokeListMethod<Map>('bondedDevices') ?? [];
    return rows
        .map((row) => BluetoothHost(
              name: row['name']?.toString() ?? 'Bluetooth device',
              address: row['address']?.toString() ?? '',
            ))
        .where((host) => host.address.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> connect(String address) =>
      _methods.invokeMethod<void>('connect', {'address': address});

  Future<void> rememberHost(String address) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastHostKey, address);
  }

  Future<String?> lastHostAddress() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_lastHostKey);
  }

  Future<void> disconnect() => _methods.invokeMethod<void>('disconnect');

  Future<void> stop() => _methods.invokeMethod<void>('stop');

  Future<bool> send(String encodedEvent) async {
    final value = jsonDecode(encodedEvent);
    if (value is! Map<String, dynamic>) return false;
    return await _methods.invokeMethod<bool>('send', {'event': value}) ?? false;
  }
}

class BluetoothHost {
  const BluetoothHost({required this.name, required this.address});
  final String name;
  final String address;
}
