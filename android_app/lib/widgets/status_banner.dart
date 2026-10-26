import 'package:flutter/material.dart';

import '../services/remote_client.dart';
import '../theme.dart';

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.snapshot});

  final LinkSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = snapshot.isConnected
        ? AppTheme.connected
        : snapshot.status == LinkStatus.disconnected
            ? AppTheme.disconnected
            : const Color(0xFFFFC857);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            snapshot.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
