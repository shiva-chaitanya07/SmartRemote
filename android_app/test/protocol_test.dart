import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_controller/protocol.dart';
import 'package:smart_controller/utils/certificate_pin.dart';
import 'package:smart_controller/utils/network_address.dart';

void main() {
  group('RemoteEvent', () {
    test('encodes keyboard and mouse events with the expected protocol', () {
      expect(jsonDecode(RemoteEvent.keyTap('a')), {'type': 'key', 'key': 'a'});
      expect(jsonDecode(RemoteEvent.keyDown('shift')), {
        'type': 'key_down',
        'key': 'shift',
      });
      expect(jsonDecode(RemoteEvent.keyUp('shift')), {
        'type': 'key_up',
        'key': 'shift',
      });
      expect(jsonDecode(RemoteEvent.mouseMove(1.5, -2)), {
        'type': 'mouse_move',
        'dx': 1.5,
        'dy': -2,
      });
      expect(jsonDecode(RemoteEvent.mouseClick('right')), {
        'type': 'mouse_click',
        'button': 'right',
      });
    });

    test('encodes text and media control events', () {
      expect(jsonDecode(RemoteEvent.text('hello')), {
        'type': 'text',
        'text': 'hello',
      });
      expect(jsonDecode(RemoteEvent.media('volume_up')), {
        'type': 'media',
        'action': 'volume_up',
      });
      expect(jsonDecode(RemoteEvent.ping()), {'type': 'ping'});
    });
  });

  group('ServerMessage.tryParse', () {
    test('reads valid server messages', () {
      final message = ServerMessage.tryParse(
        '{"type":"auth_result","status":"ok"}',
      );

      expect(message?.type, 'auth_result');
      expect(message?.status, 'ok');
    });

    test('rejects malformed or unexpected payloads without throwing', () {
      expect(ServerMessage.tryParse('not json'), isNull);
      expect(ServerMessage.tryParse('[]'), isNull);
      expect(ServerMessage.tryParse(12), isNull);
    });

    test('ignores fields with unexpected JSON types', () {
      final message = ServerMessage.tryParse(
        '{"type":12,"status":false,"message":{}}',
      );

      expect(message, isNotNull);
      expect(message?.type, '');
      expect(message?.status, isNull);
      expect(message?.message, isNull);
    });
  });

  group('isLocalNetworkAddress', () {
    test('accepts private, loopback, and link-local addresses', () {
      for (final address in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.10',
        '127.0.0.1',
        '169.254.10.20',
        'fc00::1',
        'fd12:3456::1',
        'fe80::1',
        '::1',
      ]) {
        expect(isLocalNetworkAddress(address), isTrue, reason: address);
      }
    });

    test('rejects public addresses, hostnames, and malformed input', () {
      for (final address in [
        '8.8.8.8',
        '172.32.0.1',
        '192.167.1.10',
        'example.com',
        'not-an-ip',
        '',
      ]) {
        expect(isLocalNetworkAddress(address), isFalse, reason: address);
      }
    });
  });

  group('matchesServerCertificate', () {
    test('accepts the expected SHA-256 certificate pin only', () {
      final certificateDer =
          Uint8List.fromList(utf8.encode('test-certificate'));
      final correctPin = sha256.convert(certificateDer).toString();

      expect(matchesServerCertificate(certificateDer, correctPin), isTrue);
      expect(
        matchesServerCertificate(
          certificateDer,
          correctPin.toUpperCase().replaceAllMapped(
                RegExp(r'..'),
                (match) => '${match[0]}:',
              ),
        ),
        isTrue,
      );
      expect(
        matchesServerCertificate(certificateDer, List.filled(64, '0').join()),
        isFalse,
      );
      expect(matchesServerCertificate(certificateDer, 'invalid'), isFalse);
    });
  });
}
