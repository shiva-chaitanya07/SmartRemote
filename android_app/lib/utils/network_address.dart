import 'dart:io';

/// Accepts only loopback, link-local, RFC1918 IPv4, and IPv6 ULA addresses.
bool isLocalNetworkAddress(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null) return false;
  final bytes = address.rawAddress;
  if (bytes.length == 4) {
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        first == 127 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 169 && second == 254);
  }
  return address.isLoopback ||
      address.isLinkLocal ||
      (bytes.length == 16 && (bytes[0] & 0xfe) == 0xfc);
}
