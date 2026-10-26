import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Compares the peer certificate's SHA-256 digest with an out-of-band pin.
bool matchesServerCertificate(Uint8List certificateDer, String fingerprint) {
  final expected = fingerprint
      .replaceAll(':', '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return false;
  return sha256.convert(certificateDer).toString() == expected;
}
