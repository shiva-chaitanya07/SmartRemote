import 'package:flutter/material.dart';

import '../protocol.dart';
import '../theme.dart';

class MediaBar extends StatelessWidget {
  const MediaBar({
    super.key,
    required this.enabled,
    required this.onSend,
  });

  final bool enabled;
  final void Function(String json) onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _round('volume_down', Icons.remove, enabled, onSend),
        const SizedBox(width: 10),
        Expanded(
          child: _pill(
            action: 'play_pause',
            icon: Icons.play_arrow_rounded,
            label: 'Play / Pause',
            enabled: enabled,
            onSend: onSend,
          ),
        ),
        const SizedBox(width: 10),
        _round('volume_up', Icons.add, enabled, onSend),
      ],
    );
  }

  Widget _round(
    String action,
    IconData icon,
    bool enabled,
    void Function(String json) onSend,
  ) {
    return _ActionButton(
      enabled: enabled,
      onTap: () => onSend(RemoteEvent.media(action)),
      child: Icon(icon, color: AppTheme.textPrimary),
    );
  }

  Widget _pill({
    required String action,
    required IconData icon,
    required String label,
    required bool enabled,
    required void Function(String json) onSend,
  }) {
    return _ActionButton(
      enabled: enabled,
      expand: true,
      onTap: () => onSend(RemoteEvent.media(action)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ClickBar extends StatelessWidget {
  const ClickBar({
    super.key,
    required this.enabled,
    required this.onSend,
  });

  final bool enabled;
  final void Function(String json) onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            enabled: enabled,
            expand: true,
            onTap: () => onSend(RemoteEvent.mouseClick('left')),
            child: const Text(
              'Left click',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            enabled: enabled,
            expand: true,
            onTap: () => onSend(RemoteEvent.mouseClick('right')),
            child: const Text(
              'Right click',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.enabled,
    required this.onTap,
    required this.child,
    this.expand = false,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 48,
          width: expand ? double.infinity : 48,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
    return Opacity(opacity: enabled ? 1 : 0.45, child: button);
  }
}
