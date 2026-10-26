import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../protocol.dart';
import '../theme.dart';

class VirtualKeyboard extends StatefulWidget {
  const VirtualKeyboard({
    super.key,
    required this.enabled,
    required this.onSend,
  });

  final bool enabled;
  final void Function(String json) onSend;

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard> {
  bool _shift = false;
  bool _symbols = false;

  static const _letters = [
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  static const _digits = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['-', '/', ':', ';', '(', ')', r'$', '&', '@', '"'],
    ['.', ',', '?', '!', "'", '#', '%'],
  ];

  void _tapChar(String value) {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    final out = _shift ? value.toUpperCase() : value;
    widget.onSend(RemoteEvent.keyTap(out));
    if (_shift) setState(() => _shift = false);
  }

  void _tapSpecial(String key) {
    if (!widget.enabled) return;
    HapticFeedback.lightImpact();
    widget.onSend(RemoteEvent.keyTap(key));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _symbols ? _digits : _letters;
    return AbsorbPointer(
      absorbing: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: Column(
          children: [
            _row([
              _KeySpec('esc', flex: 1.1, special: true),
              _KeySpec('tab', flex: 1.1, special: true),
              _KeySpec('up', label: '↑', special: true),
              _KeySpec('down', label: '↓', special: true),
              _KeySpec('left', label: '←', special: true),
              _KeySpec('right', label: '→', special: true),
            ]),
            const SizedBox(height: 6),
            ...rows.asMap().entries.map((entry) {
              final index = entry.key;
              final keys = entry.value;
              final specs = <_KeySpec>[
                if (index == 2)
                  _KeySpec(
                    'shift',
                    label: _shift ? '⇧' : 'shift',
                    flex: 1.35,
                    special: true,
                    highlighted: _shift,
                  ),
                ...keys.map(
                    (k) => _KeySpec(k, label: _shift ? k.toUpperCase() : k)),
                if (index == 2)
                  _KeySpec('backspace', label: '⌫', flex: 1.35, special: true),
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _row(specs),
              );
            }),
            _row([
              _KeySpec(
                '123',
                label: _symbols ? 'ABC' : '?123',
                flex: 1.4,
                special: true,
              ),
              _KeySpec('space', label: 'space', flex: 5, special: true),
              _KeySpec('enter', label: 'enter', flex: 1.8, special: true),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _row(List<_KeySpec> keys) {
    return Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(flex: (keys[i].flex * 100).round(), child: _key(keys[i])),
        ],
      ],
    );
  }

  Widget _key(_KeySpec spec) {
    return Material(
      color: spec.highlighted ? AppTheme.accent : AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          if (spec.key == 'shift') {
            setState(() => _shift = !_shift);
            return;
          }
          if (spec.key == '123') {
            setState(() => _symbols = !_symbols);
            return;
          }
          if (spec.special && spec.key.length > 1) {
            _tapSpecial(spec.key);
          } else {
            _tapChar(spec.key);
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 42,
          child: Center(
            child: Text(
              spec.label,
              style: TextStyle(
                color: spec.highlighted ? Colors.white : AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: spec.label.length > 1 ? 12 : 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeySpec {
  _KeySpec(
    this.key, {
    String? label,
    this.flex = 1,
    this.special = false,
    this.highlighted = false,
  }) : label = label ?? key;

  final String key;
  final String label;
  final double flex;
  final bool special;
  final bool highlighted;
}
