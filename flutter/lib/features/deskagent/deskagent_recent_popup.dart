import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_icons.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_tokens.dart';
import 'package:flutter_hbb/models/state_model.dart';

/// Secondary window of the widget: `Thiết bị gần đây` (380x220, frameless).
///
/// Design doc (bao-cao-ux): the recent-peers dropdown is its own popup window,
/// opening upward with its bottom pinned 4px above the input row of the panel.
/// Tapping a peer starts a session through the main window (`kWindowConnect`).
/// The main window pushes an updated peer list via `recent-peers-refresh`.
class RecentPeersWindow extends StatefulWidget {
  RecentPeersWindow(this.argument, {Key? key}) : super(key: key);

  final Map<String, dynamic> argument;

  @override
  State<StatefulWidget> createState() => _RecentPeersWindowState();
}

class _RecentPeersWindowState extends State<RecentPeersWindow> {
  static const Color _header = Color(0xFF1A1A1E);
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
        // Sender gửi jsonEncode string — decode thống nhất với Map.
        final args = call.arguments;
        final map = args is Map
            ? args.cast<dynamic, dynamic>()
            : (args is String
                ? (jsonDecode(args) as Map).cast<dynamic, dynamic>()
                : null);
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
    try {
      WindowController.fromWindowId(stateGlobal.windowId).close();
    } catch (_) {}
  }

  void _connectPeer(String id) {
    // Main window id in desktop_multi_window is always 0.
    DesktopMultiWindow.invokeMethod(
      0,
      kWindowConnect,
      jsonEncode({
        'id': id,
        'isFileTransfer': false,
        'isViewCamera': false,
        'isTerminal': false,
        'isTcpTunneling': false,
        'isRDP': false,
        'password': '',
        'forceRelay': false,
        'connToken': '',
      }),
    );
    _closeSelf();
  }

  @override
  Widget build(BuildContext context) {
    final peers = _peers;
    return Scaffold(
      backgroundColor: DeskAgentFluentColors.window,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            // Header 26 "Thiết bị gần đây" (client-widget.html:1834).
            height: 26,
            padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
            color: _header,
            child: Row(
              children: [
                const Text(
                  'Thiết bị gần đây',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: DeskAgentFluentColors.textPrimary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _closeSelf,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: DeskAgentIcons.x(
                      size: 12,
                      color: DeskAgentFluentColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: peers.isEmpty
                ? Center(
                    child: Text(
                      'Không có thiết bị gần đây',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: DeskAgentFluentColors.textSecondary,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final p in peers.take(4))
                          InkWell(
                            onTap: () => _connectPeer('${p['id'] ?? ''}'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              child: Row(
                                children: [
                                  DeskAgentIcons.monitor(
                                    size: 14,
                                    color: DeskAgentFluentColors.accent,
                                  ),
                                  const SizedBox(width: 8),
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
                                            color: DeskAgentFluentColors
                                                .textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '${p['id'] ?? ''}',
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontFamily: _mono,
                                            fontSize: 10.5,
                                            color: DeskAgentFluentColors
                                                .textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(
                                        right: 4, left: 8),
                                    decoration: BoxDecoration(
                                      color: p['online'] == true
                                          ? DeskAgentFluentColors.success
                                          : DeskAgentFluentColors.danger,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Text(
                                    p['online'] == true ? 'Online' : 'Offline',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color:
                                          DeskAgentFluentColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
