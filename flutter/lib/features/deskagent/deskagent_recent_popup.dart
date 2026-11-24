import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_icons.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';

/// Secondary window of the widget: the `Thiết bị gần đây` dropdown of
/// `showcase/client-widget.html` (`.recent-dropdown`: 356px wide, 8px radius,
/// light mica surface, uppercase header with a `Xóa` action).
///
/// Tapping a peer starts a session through the main window (`kWindowConnect`);
/// the main window pushes an updated peer list via `recent-peers-refresh`.
class RecentPeersWindow extends StatefulWidget {
  RecentPeersWindow(this.argument, {Key? key}) : super(key: key);

  final Map<String, dynamic> argument;

  @override
  State<StatefulWidget> createState() => _RecentPeersWindowState();
}

class _RecentPeersWindowState extends State<RecentPeersWindow> {
  // Fluent Dark palette of popup-windows-goc.html, matching the docked widget.
  static const Color _bg = Color(0xFF202020);
  static const Color _headerBg = Color(0xFF181818);
  static const Color _border = Color(0x1FFFFFFF);
  static const Color _borderStrong = Color(0x24FFFFFF);
  static const Color _text = Color(0xFFF4F4F5);
  static const Color _muted = Color(0xFFA1A1AA);
  static const Color _textSubtle = Color(0xFF71717A);
  static const Color _blue = Color(0xFF60CDFF);
  static const Color _blueLight = Color(0x14FFFFFF);
  static const Color _green = Color(0xFF34D399);
  static const String _mono = 'Consolas';

  List<Map<String, dynamic>> _peers = [];

  @override
  void initState() {
    super.initState();
    _peers = _parse(widget.argument['peers']);
    // The main window feeds an updated list every time the ID input gains
    // focus (existing window is shown instead of re-created).
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'recent-peers-refresh') {
        final args = call.arguments;
        final map = args is Map ? args : null;
        final list = _parse(map?['peers']);
        if (mounted) setState(() => _peers = list);
      }
    });
  }

  @override
  void dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    super.dispose();
  }

  List<Map<String, dynamic>> _parse(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  void _closeSelf() {
    DesktopMultiWindow.invokeMethod(
        0, 'recent-peers-closed', <String, dynamic>{});
    try {
      WindowController.fromWindowId(stateGlobal.windowId).close();
    } catch (_) {}
  }

  void _connectPeer(String id) {
    if (id.isEmpty) return;
    // Main window id in desktop_multi_window is always 0.
    // Arguments must be a Map: the main window handler reads
    // call.arguments['id'] (same convention as rustDeskWinManager.call).
    DesktopMultiWindow.invokeMethod(0, kWindowConnect, {
      'id': id,
      'isFileTransfer': false,
      'isViewCamera': false,
      'isTerminal': false,
      'isTcpTunneling': false,
      'isRDP': false,
      'password': '',
      'forceRelay': false,
      'connToken': '',
    });
    _closeSelf();
  }

  /// `Xóa` in the mockup header: forget every listed peer through the real
  /// recent-peers store, then empty the list.
  Future<void> _clearHistory() async {
    for (final p in _peers) {
      final id = '${p['id'] ?? ''}';
      if (id.isEmpty) continue;
      try {
        await bind.mainRemovePeer(id: id);
      } catch (_) {}
    }
    if (mounted) setState(() => _peers = []);
  }

  @override
  Widget build(BuildContext context) {
    final peers = _peers;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: _bg,
          border: Border.all(color: _borderStrong),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x47000000),
              blurRadius: 36,
              offset: Offset(0, 16),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 26,
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              decoration: const BoxDecoration(
                color: _headerBg,
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'THIẾT BỊ GẦN ĐÂY',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _textSubtle,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _clearHistory,
                    borderRadius: BorderRadius.circular(3),
                    hoverColor: const Color(0x0FFFFFFF),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Xóa',
                        style: TextStyle(fontSize: 10.5, color: _muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: peers.isEmpty
                  ? const Center(
                      child: Text(
                        'Không có thiết bị gần đây',
                        style: TextStyle(fontSize: 11.5, color: _textSubtle),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(4),
                      children: [
                        for (final p in peers.take(4))
                          InkWell(
                            onTap: () => _connectPeer('${p['id'] ?? ''}'),
                            borderRadius: BorderRadius.circular(8),
                            hoverColor: _blueLight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: _blueLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: DeskAgentIcons.monitor(
                                          size: 13, color: _blue),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${p['name'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _text,
                                            height: 1.25,
                                          ),
                                        ),
                                        Text(
                                          '${p['id'] ?? ''}',
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontFamily: _mono,
                                            fontSize: 11,
                                            color: _muted,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: p['online'] == true
                                              ? _green
                                              : _textSubtle,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        p['online'] == true
                                            ? 'Online'
                                            : 'Offline',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: p['online'] == true
                                              ? _green
                                              : _textSubtle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
