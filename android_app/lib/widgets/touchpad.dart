import 'package:flutter/material.dart';

import '../protocol.dart';
import '../theme.dart';

class Touchpad extends StatefulWidget {
  const Touchpad({
    super.key,
    required this.enabled,
    required this.onSend,
  });

  final bool enabled;
  final void Function(String json) onSend;

  @override
  State<Touchpad> createState() => _TouchpadState();
}

class _PointerTrack {
  _PointerTrack(this.start, this.last)
      : downAt = DateTime.now(),
        moved = false;

  final Offset start;
  Offset last;
  final DateTime downAt;
  bool moved;
}

class _TouchpadState extends State<Touchpad> {
  static const double _moveSlop = 12;
  static const double _sensitivity = 1.35;
  static const double _scrollSensitivity = 0.08;

  final Map<int, _PointerTrack> _pointers = {};
  bool _multiTouchGesture = false;
  bool _multiTouchMoved = false;
  double _scrollX = 0;
  double _scrollY = 0;

  void _handleDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _pointers[event.pointer] =
        _PointerTrack(event.localPosition, event.localPosition);
    if (_pointers.length >= 2) _multiTouchGesture = true;
  }

  void _handleMove(PointerMoveEvent event) {
    if (!widget.enabled) return;
    final track = _pointers[event.pointer];
    if (track == null) return;

    final delta = event.localPosition - track.last;
    track.last = event.localPosition;
    if ((track.last - track.start).distance > _moveSlop) {
      track.moved = true;
      if (_multiTouchGesture) _multiTouchMoved = true;
    }

    if (_pointers.length == 1 &&
        (delta.dx.abs() > 0.2 || delta.dy.abs() > 0.2)) {
      widget.onSend(
        RemoteEvent.mouseMove(delta.dx * _sensitivity, delta.dy * _sensitivity),
      );
    } else if (_pointers.length >= 2) {
      _scrollX += delta.dx * _scrollSensitivity;
      _scrollY -= delta.dy * _scrollSensitivity;
      final scrollX = _scrollX.truncateToDouble();
      final scrollY = _scrollY.truncateToDouble();
      if (scrollX != 0 || scrollY != 0) {
        _scrollX -= scrollX;
        _scrollY -= scrollY;
        widget.onSend(RemoteEvent.mouseScroll(scrollX, scrollY));
      }
    }
  }

  void _handleUp(PointerEvent event) {
    final track = _pointers.remove(event.pointer);
    if (track == null || !widget.enabled) return;

    final elapsed = DateTime.now().difference(track.downAt);
    final wasTap = !track.moved && elapsed < const Duration(milliseconds: 280);
    if (!wasTap) return;

    if (_multiTouchGesture) {
      if (!wasTap) _multiTouchMoved = true;
      if (_pointers.isEmpty) {
        if (!_multiTouchMoved) widget.onSend(RemoteEvent.mouseClick('right'));
        _multiTouchGesture = false;
        _multiTouchMoved = false;
      }
    } else if (wasTap) {
      widget.onSend(RemoteEvent.mouseClick('left'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        if (_pointers.isEmpty) {
          _multiTouchGesture = false;
          _multiTouchMoved = false;
          _scrollX = 0;
          _scrollY = 0;
        }
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: widget.enabled ? 1 : 0.45,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.surfaceAlt,
                AppTheme.surface,
                Color(0xFF14151C),
              ],
            ),
          ),
          child: CustomPaint(
            painter: _GridPainter(),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mouse_outlined,
                      color: AppTheme.textMuted, size: 28),
                  SizedBox(height: 8),
                  Text(
                    'Touchpad',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Drag to move · tap click · two-finger scroll / right-click',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
