import 'package:flutter/material.dart';

import 'deskagent_tokens.dart';

/// Single in-session action bar for Windows.
///
/// The native Windows titlebar stays responsible for move / minimize /
/// maximize / close, so this bar only hosts the real RemoteToolbar actions
/// (pin, monitor, control, display, keyboard, chat, voice, record, tools,
/// disconnect). Keeping one bar avoids the duplicate titlebar that used to
/// drop actions and fight the native frame.
class DeskAgentActionBar extends StatelessWidget {
  final List<Widget> items;
  final bool isHorizontal;
  final String? fps;

  /// Docks the bar as a full-width command strip under the tab bar (top edge).
  final bool docked;

  const DeskAgentActionBar({
    Key? key,
    required this.items,
    required this.isHorizontal,
    this.fps,
    this.docked = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (docked) {
      return Container(
        width: double.infinity,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: const BoxDecoration(
          color: DeskAgentFluentColors.deepSurface,
          border: Border(
              bottom: BorderSide(color: DeskAgentFluentColors.border8)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 2),
            _FpsBadge(fps: fps),
            const SizedBox(width: 6),
            _verticalSeparator(),
            const SizedBox(width: 2),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: items),
              ),
            ),
          ],
        ),
      );
    }
    final children = <Widget>[
      const SizedBox(width: 4, height: 4),
      _FpsBadge(fps: fps),
      const SizedBox(width: 4, height: 4),
      _separator(),
      ...items,
      const SizedBox(width: 4, height: 4),
    ];
    final content = isHorizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: children)
        : Column(mainAxisSize: MainAxisSize.min, children: children);

    return Container(
      decoration: BoxDecoration(
        color: DeskAgentFluentColors.window,
        borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusCard),
        border: Border.all(color: DeskAgentFluentColors.border8),
        boxShadow: const [
          BoxShadow(
              color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 4))
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: isHorizontal ? Axis.horizontal : Axis.vertical,
        child: content,
      ),
    );
  }

  Widget _verticalSeparator() => Container(
        width: 1,
        height: 14,
        color: DeskAgentFluentColors.border8,
      );

  Widget _separator() => Container(
        width: isHorizontal ? 1 : 14,
        height: isHorizontal ? 14 : 1,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        color: DeskAgentFluentColors.border8,
      );
}

class _FpsBadge extends StatelessWidget {
  final String? fps;

  const _FpsBadge({required this.fps});

  @override
  Widget build(BuildContext context) {
    final value = fps?.trim() ?? '';
    final shown = value.isEmpty ? '-- FPS' : '${value.split(' ').first} FPS';
    final success = DeskAgentFluentColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: success.withOpacity(0.25)),
      ),
      child: Text(shown,
          style: TextStyle(
              fontFamily: 'Consolas',
              color: success,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
    );
  }
}
