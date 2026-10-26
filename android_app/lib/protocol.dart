import 'dart:convert';

/// JSON protocol shared with the Python Windows server.
class RemoteEvent {
  RemoteEvent._();

  static String encode(Map<String, dynamic> payload) => jsonEncode(payload);

  static String ping() => encode({'type': 'ping'});

  static String keyTap(String key) => encode({'type': 'key', 'key': key});

  static String keyDown(String key) => encode({'type': 'key_down', 'key': key});

  static String keyUp(String key) => encode({'type': 'key_up', 'key': key});

  static String text(String value) => encode({'type': 'text', 'text': value});

  static String mouseMove(double dx, double dy) => encode({
        'type': 'mouse_move',
        'dx': dx,
        'dy': dy,
      });

  static String mouseClick(String button) => encode({
        'type': 'mouse_click',
        'button': button,
      });

  static String mouseDown(String button) => encode({
        'type': 'mouse_down',
        'button': button,
      });

  static String mouseUp(String button) => encode({
        'type': 'mouse_up',
        'button': button,
      });

  static String mouseScroll(double dx, double dy) => encode({
        'type': 'mouse_scroll',
        'dx': dx,
        'dy': dy,
      });

  static String media(String action) => encode({
        'type': 'media',
        'action': action,
      });
}

class ServerMessage {
  ServerMessage({required this.type, this.status, this.message});

  final String type;
  final String? status;
  final String? message;

  static ServerMessage? tryParse(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map<String, dynamic>) return null;
      return ServerMessage(
        type: decoded['type'] as String? ?? '',
        status: decoded['status'] as String?,
        message: decoded['message'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
