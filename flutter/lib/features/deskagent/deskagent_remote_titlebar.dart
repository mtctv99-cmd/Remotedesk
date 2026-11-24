import 'package:flutter/material.dart';

import 'package:flutter_hbb/models/model.dart';
import 'deskagent_icons.dart';
import 'deskagent_tokens.dart';
import 'deskagent_win11.dart';

/// DeskAgent remote-session titlebar, matched to `remote-session-goc.html`:
/// a 32px dark bar with the peer id, a live FPS badge, the four IT actions
/// (display / monitor / shortcuts / tools), pin and native caption buttons.
///
/// Presentation only: it takes the real, already-wired action widgets from
/// RemoteToolbar as children and never touches the FFI / frame lifecycle.
class DeskAgentRemoteTitlebar extends StatelessWidget {
  final FFI ffi;
  final String peerName;
  final Widget monitorAction;
  final Widget displayAction;
  final Widget shortcutAction;
  final Widget toolsAction;
  final Widget pinAction;
  final Widget closeAction;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;

  const DeskAgentRemoteTitlebar({
    Key? key,
    required this.ffi,
    required this.peerName,
    required this.monitorAction,
    required this.displayAction,
    required this.shortcutAction,
    required this.toolsAction,
    required this.pinAction,
    required this.closeAction,
    required this.onMinimize,
    required this.onToggleMaximize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DeskAgentMetrics.titlebarHeight,
      decoration: BoxDecoration(
        color: DeskAgentFluentColors.window,
        borderRadius:
            const BorderRadius.all(Radius.circular(DeskAgentMetrics.radiusButton)),
        border: const Border(
            bottom: BorderSide(color: DeskAgentFluentColors.border8, width: 1)),
        boxShadow: const [
          BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 10),
          DeskAgentIcons.brandLogo(size: 16),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              peerName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: DeskAgentFluentColors.titlebarText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _FpsBadge(fps: ffi.qualityMonitorModel.data.fps),
          const SizedBox(width: 10),
          _barAction('Màn 1', monitorAction),
          _barAction('Hiển thị', displayAction),
          _barAction('Phím tắt', shortcutAction),
          _barAction('Tool', toolsAction),
          const SizedBox(width: 4),
          SizedBox(width: 26, height: 26, child: pinAction),
          const SizedBox(width: 4),
          Container(
              width: 1, height: 14, color: DeskAgentFluentColors.border8),
          Win11CaptionButton(
              icon: Icons.remove,
              tooltip: 'Thu nhỏ cửa sổ',
              onPressed: onMinimize),
          Win11CaptionButton(
              icon: Icons.crop_square,
              tooltip: 'Phóng to / Cửa sổ',
              onPressed: onToggleMaximize),
          // Uses the real disconnect action from RemoteToolbar.
          SizedBox(
              width: 46,
              height: DeskAgentMetrics.titlebarHeight,
              child: closeAction),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _barAction(String label, Widget action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 18, height: 22, child: action),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: DeskAgentFluentColors.titlebarTextSecondary)),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: success, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(shown,
              style: TextStyle(
                  color: success, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
