import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/chat_page.dart';
import 'package:flutter_hbb/features/deskagent/ai_chat_page.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_config.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_icons.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_tokens.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

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
  bool _eventsLoading = false;
  String _eventsState = 'idle'; // idle | loading | data | empty | error | no-token
  String _eventsError = '';
  List<Map<String, dynamic>> _events = [];
  final HttpClient _http = HttpClient();

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
                child: switch (_tab) {
                  0 => const AiChatPage(embedded: true),
                  1 => ChatPage(
                      chatModel: widget.ffi.chatModel,
                      type: null,
                    ),
                  _ => _eventsBody(),
                },
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

  /// GET /api/client/peer-data for the connected peer's hostname, using this
  /// client's device token (mirrored to the local option store on register).
  Future<void> _loadRemoteEvents() async {
    if (_eventsLoading) return;
    setState(() {
      _eventsLoading = true;
      _eventsError = '';
    });
    try {
      final hostname = widget.ffi.ffiModel.pi.hostname;
      if (hostname.isEmpty) {
        setState(() => _eventsState = 'no-host');
        return;
      }
      final token = bind.mainGetLocalOption(key: 'manager-device-token');
      if (token.isEmpty) {
        setState(() => _eventsState = 'no-token');
        return;
      }
      final uri = Uri.parse('$kApiBase/client/peer-data')
          .replace(queryParameters: {'hostname': hostname});
      final req = await _http.getUrl(uri);
      req.headers.set('X-Device-Token', token);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw 'HTTP ${resp.statusCode}: $body';
      }
      final map = jsonDecode(body) as Map<dynamic, dynamic>;
      final list = ((map['events'] as List? ?? []))
          .cast<Map<dynamic, dynamic>>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      setState(() {
        _events = list;
        _eventsState = list.isEmpty ? 'empty' : 'data';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _eventsState = 'error';
          _eventsError = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _eventsLoading = false);
      }
    }
  }

  Widget _eventsBody() {
    if (_eventsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_eventsState == 'no-token') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Chưa có manager-device-token: client cần đăng ký lại Manager',
            style: TextStyle(
                fontSize: 11.5, color: DeskAgentFluentColors.textSecondary),
          ),
        ),
      );
    }
    if (_eventsState == 'empty') {
      return const Center(
        child: Text(
          'Không có sự kiện nào',
          style: TextStyle(
              fontSize: 11.5, color: DeskAgentFluentColors.textSecondary),
        ),
      );
    }
    if (_eventsState == 'error') {
      return Center(
        child: Text(
          'Lỗi: $_eventsError',
          style: const TextStyle(
              fontSize: 11.5, color: DeskAgentFluentColors.danger),
        ),
      );
    }
    return ListView.builder(
      itemCount: _events.length,
      itemBuilder: (context, i) {
        final e = _events[i];
        final created = e['created_at'];
        final time = created is int && created > 0
            ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
            : null;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: DeskAgentFluentColors.border8))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: DeskAgentFluentColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${e['source'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontFamily: 'Consolas',
                    color: DeskAgentFluentColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${e['text'] ?? ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: DeskAgentFluentColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                time == null ? '' : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'Consolas',
                  color: DeskAgentFluentColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
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
          const SizedBox(width: 4),
          _tabButton(
              2,
              'Sự kiện',
              ({Color? color}) => DeskAgentIcons.bell(color: color ?? Colors.transparent)),
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
      onTap: () {
        setState(() => _tab = index);
        if (index == 2) {
          _loadRemoteEvents();
        }
      },
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
