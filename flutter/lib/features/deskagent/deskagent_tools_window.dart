import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/chat_page.dart';
import 'package:flutter_hbb/features/deskagent/ai_chat_page.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_icons.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_tokens.dart';
import 'package:flutter_hbb/models/model.dart';

/// Toggle shared by the remote toolbar (Tool button) and the in-session
/// overlay in remote_page. Real behavior only: both tabs talk to real
/// backends (Manager REST / session chat), no mock panels.
class DeskAgentTools {
  static final ValueNotifier<bool> visible = ValueNotifier(false);
}

/// Floating Tools Window for the remote session — 580x420, Win11 Fluent Dark.
/// This wave ships the two tabs with real backends (Trợ lý AI = Manager REST,
/// Chat IT = session chat). The mockup's Sự kiện / Deploy tabs need the
/// Manager peer-data token on the client / the upload API and follow when
/// those endpoints are reachable.
class DeskAgentToolsWindow extends StatefulWidget {
  const DeskAgentToolsWindow({
    Key? key,
    required this.ffi,
    required this.onClose,
  }) : super(key: key);

  final FFI ffi;
  final VoidCallback onClose;

  @override
  State<StatefulWidget> createState() => _DeskAgentToolsWindowState();
}

class _DeskAgentToolsWindowState extends State<DeskAgentToolsWindow> {
  static const Color bg = Color(0xFF242424);
  static const Color bar = Color(0xFF1C1C1C);
  static const Color line = Color(0x14FFFFFF);
  static const double width = 580;
  static const double height = 420;

  int _tab = 0;
  Offset _pos = const Offset(110, 70);
  Offset? _dragFrom;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: bg,
          elevation: 10,
          shadowColor: Colors.black,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titlebar(),
              _tabHeader(),
              Expanded(
                child: _tab == 0
                    ? const AiChatPage(embedded: true)
                    : ChatPage(
                        chatModel: widget.ffi.chatModel,
                        type: null,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titlebar() {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _dragFrom = e.position;
          _dragging = false;
        },
        onPointerMove: (e) {
          if (_dragFrom == null) return;
          if (!_dragging && (e.position - _dragFrom!).distance > 4) {
            _dragging = true;
          }
          if (_dragging) {
            setState(() {
              _pos = Offset(
                (_pos.dx + e.position.dx - _dragFrom!.dx)
                    .clamp(0.0, 2400.0),
                (_pos.dy + e.position.dy - _dragFrom!.dy)
                    .clamp(0.0, 1400.0),
              );
              _dragFrom = e.position;
            });
          }
        },
        onPointerUp: (_) {
          _dragFrom = null;
          _dragging = false;
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bar,
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              const Text(
                'Tools • DeskAgent',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DeskAgentFluentColors.textPrimary,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                child: DeskAgentIcons.x(
                  size: 14,
                  color: DeskAgentFluentColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bar,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          _tabButton(
              0,
              'Trợ lý AI',
              ({Color? color}) => DeskAgentIcons.sparkles(color: color ?? Colors.transparent)),
          const SizedBox(width: 4),
          _tabButton(
              1,
              'Chat IT',
              ({Color? color}) => DeskAgentIcons.message(color: color ?? Colors.transparent)),
        ],
      ),
    );
  }

  Widget _tabButton(
      int index, String label, Widget Function({Color? color}) icon) {
    final active = _tab == index;
    final color = active
        ? DeskAgentFluentColors.accent
        : DeskAgentFluentColors.textSecondary;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? DeskAgentFluentColors.accent.withOpacity(0.18)
              : Colors.transparent,
          border: Border(
              bottom: BorderSide(
                  color: active
                      ? DeskAgentFluentColors.accent
                      : Colors.transparent,
                  width: 2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon(color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
