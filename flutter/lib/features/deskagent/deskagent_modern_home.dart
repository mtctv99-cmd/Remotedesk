import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/autocomplete.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'ai_chat_page.dart';
import 'deskagent_config.dart';
import 'deskagent_icons.dart';
import 'deskagent_window_mode.dart';

/// Palette of the shipped pill/panel (`pill-old-click.png`): dark surface with
/// the Win11 cyan accent; the connect button uses dark text on cyan.
class _PillPalette {
  static const Color bg = Color(0xFF202020);
  static const Color chip = Color(0xFF2A2A2E);
  static const Color border = Color(0x1FFFFFFF); // white 12%
  static const Color text = Color(0xFFF4F4F5);
  static const Color muted = Color(0xFFA1A1AA);
  static const Color accent = Color(0xFF60CDFF);
  static const Color accentText = Color(0xFF0B0B0B);
  static const String mono = 'Consolas';
}

/// Client widget palette, taken from `showcase/client-widget.html`
/// ("Trắng – Cam – Xanh"): a light mica surface with a blue primary and an
/// orange call-to-action. Kept local to the widget so the app-wide theme (which
/// also serves the dark remote session and dialogs) stays untouched.
class _WidgetPalette {
  static const Color bg = Color(0xFFF9F9F9);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1A1A1A);
  static const Color muted = Color(0xFF6B7280);
  static const Color border = Color(0x24000000); // black 14%
  static const Color blue = Color(0xFF0284C7);
  static const Color blueDark = Color(0xFF0369A1);
  static const Color orange = Color(0xFFF97316);
  static const Color orangeDark = Color(0xFFEA580C);
  static const Color green = Color(0xFF10B981);
  static const String mono = 'Consolas';
}


/// Modern DeskAgent Home Widget tailored for the docked bottom-right client window.
/// Provides a sleek single-column card layout:
/// - My Device ID & Password (with 1-click copy for IT support)
/// - Remote Control (Connect input + actions)
/// - Recent Sessions
/// No tab bar: AI Chat / About / Event Viewer open as one full-area overlay
/// (contract §2: header + connect area + one stretched content area).
class DeskAgentModernHome extends StatefulWidget {
  const DeskAgentModernHome({Key? key}) : super(key: key);

  @override
  State<DeskAgentModernHome> createState() => _DeskAgentModernHomeState();
}

class _DeskAgentModernHomeState extends State<DeskAgentModernHome> {
  bool _showPassword = true;

  final IDTextEditingController _remoteIdController = IDTextEditingController();
  final FocusNode _remoteIdFocusNode = FocusNode();
  final AllPeersLoader _peersLoader = AllPeersLoader();
  /// Peers dismissed with "Xóa" in the recent dropdown (this session only).
  final Set<String> _hiddenRecent = <String>{};

  /// First non-loopback IPv4 of this machine, shown in the panel's IP chip.
  String _localIp = '';

  Timer? _statusTimer;
  bool _statusRefreshing = false;
  bool _deviceIdLoaded = false;

  @override
  void initState() {
    super.initState();
    _peersLoader.init(setState);
    _remoteIdFocusNode.addListener(() {
      if (_remoteIdFocusNode.hasFocus && _peersLoader.needLoad) {
        _peersLoader.getAllPeers();
      }
      // The recent-peers dropdown follows the field's focus.
      if (mounted) setState(() {});
    });

    // Load last remote ID if available
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadLocalIp();
      try {
        final lastId = await bind.mainGetLastRemoteId();
        if (lastId.isNotEmpty && _remoteIdController.id.isEmpty) {
          setState(() {
            _remoteIdController.id = lastId;
          });
        }
      } catch (_) {}
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshStatus();
    });
    _refreshStatus();
  }

  /// Refresh the online badge of the device card.
  ///
  /// [Note]
  /// The home card renders the device ID and the online badge, but this
  /// page never mounts `_OnlineStatusWidgetState`, the only other writer
  /// of `stateGlobal.svcStatus` and the only other caller of
  /// `serverModel.fetchID`.
  Future<void> _refreshStatus() async {
    if (!mounted || _statusRefreshing) {
      return;
    }
    _statusRefreshing = true;
    try {
      final status = await _readConnectStatus();
      if (status == null) {
        return;
      }
      final statusNum = status['status_num'];
      stateGlobal.svcStatus.value = statusNum == 1
          ? SvcStatus.ready
          : statusNum == 0
              ? SvcStatus.connecting
              : SvcStatus.notReady;
      // The device ID only exists once the service is up, and it does not
      // change afterwards, so it is read once instead of on every poll.
      if (stateGlobal.svcStatus.value == SvcStatus.ready && !_deviceIdLoaded) {
        _deviceIdLoaded = true;
        await gFFI.serverModel.fetchID();
      }
      if (mounted) {
        setState(() {});
      }
    } finally {
      _statusRefreshing = false;
    }
  }

  /// The connect status reported by the core, or null when the core
  /// answered with something that cannot be read.
  Future<Map<String, dynamic>?> _readConnectStatus() async {
    try {
      final raw = await bind.mainGetConnectStatus();
      if (raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('failed to read the connect status: $e');
      return null;
    }
  }

  /// Resolve the LAN address shown next to the "IP" badge in the panel.
  Future<void> _loadLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final itf in interfaces) {
        for (final addr in itf.addresses) {
          if (!addr.isLoopback) {
            if (mounted) setState(() => _localIp = addr.address);
            return;
          }
        }
      }
    } catch (_) {
      // Keep the placeholder; the panel still works without an address.
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _remoteIdController.dispose();
    _remoteIdFocusNode.dispose();
    _peersLoader.clear();
    super.dispose();
  }

  void _onConnect({
    bool isFileTransfer = false,
    bool isTerminal = false,
    bool isViewCamera = false,
    bool isTcpTunneling = false,
  }) {
    final id = _remoteIdController.id.trim();
    if (id.isEmpty) {
      showToast(translate('Please enter remote ID'));
      return;
    }
    connect(
      context,
      id,
      isFileTransfer: isFileTransfer,
      isTerminal: isTerminal,
      isViewCamera: isViewCamera,
      isTcpTunneling: isTcpTunneling,
    );
  }

  bool get _isDockedWidget =>
      isDesktop &&
      desktopType == DesktopType.main &&
      bind.mainGetLocalOption(key: kOptionDeskAgentWidgetMode) != 'N';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PillPalette.bg,
      body: Obx(() {
        final mode = deskAgentWindowMode.value;
        if (_isDockedWidget && mode == DeskAgentWindowMode.pill) {
          return _buildPill(context);
        }
        if (_isDockedWidget) {
          return Column(
            children: [
              _buildPanel(context),
              if (mode == DeskAgentWindowMode.expanded)
                Expanded(child: _buildChatBody(context)),
            ],
          );
        }
        // Main window with widget mode off keeps the settings-style home.
        return _buildHomeTab(context);
      }),
    );
  }

  /// 86x40 "Hỗ trợ" pill, exactly as the shipped build (`pill_final.png`).
  Widget _buildPill(BuildContext context) {
    Offset? downAt;
    bool dragging = false;
    return Listener(
      onPointerDown: (e) {
        downAt = e.position;
        dragging = false;
      },
      onPointerMove: (e) {
        if (downAt != null && !dragging) {
          if ((e.position - downAt!).distance > 6) {
            dragging = true;
            windowManager.startDragging();
          }
        }
      },
      onPointerUp: (e) {
        final d = downAt;
        downAt = null;
        if (!dragging && d != null && (e.position - d).distance <= 6) {
          setDeskAgentWindowMode(DeskAgentWindowMode.compact);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: _PillPalette.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _PillPalette.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DeskAgentIcons.headphones(size: 17, color: _PillPalette.accent),
            const SizedBox(width: 5),
            const Text(
              'Hỗ trợ',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _PillPalette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Right-click menu of the pill: "Đóng (Chạy ngầm)" (pill_menu_open.png).
  void _showPillMenu(BuildContext context, Offset at) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        at.dx - 160,
        at.dy - 48,
        overlay.size.width - at.dx,
        overlay.size.height - at.dy,
      ),
      color: _PillPalette.chip,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem<String>(
          value: 'hide',
          height: 34,
          onTap: () => windowManager.hide(),
          child: Row(
            children: [
              DeskAgentIcons.x(size: 13, color: _PillPalette.text),
              const SizedBox(width: 8),
              const Text(
                'Đóng (Chạy ngầm)',
                style: TextStyle(fontSize: 12, color: _PillPalette.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 380x96 panel the pill expands into (`pill-old-click.png`):
  /// [monitor] [IP chip] [Hỗ trợ] over [monitor] [ID input] [Kết nối].
  Widget _buildPanel(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        color: _PillPalette.bg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  DeskAgentIcons.monitor(size: 16, color: _PillPalette.accent),
                  const SizedBox(width: 10),
                  Expanded(child: _buildIpChip()),
                  const SizedBox(width: 8),
                  _buildHelpPill(),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  DeskAgentIcons.monitor(size: 15, color: _PillPalette.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _remoteIdController,
                      focusNode: _remoteIdFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [IDTextInputFormatter()],
                      style: const TextStyle(
                        fontFamily: _PillPalette.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _PillPalette.text,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Nhập ID máy cần điều khiển...',
                        hintStyle: TextStyle(
                          fontFamily: _PillPalette.mono,
                          fontSize: 11.5,
                          color: _PillPalette.muted,
                        ),
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _onConnect(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _onConnect,
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _PillPalette.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DeskAgentIcons.headphones(
                            size: 13,
                            color: _PillPalette.accentText,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Kết nối',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _PillPalette.accentText,
                            ),
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

  /// Dark chip `IP <addr> | <password>` from the approved screenshot.
  Widget _buildIpChip() {
    final pass = gFFI.serverModel.serverPasswd.text.trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: _PillPalette.chip,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _PillPalette.accent,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'IP',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _PillPalette.accentText,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _localIp.isEmpty ? '---' : _localIp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _PillPalette.mono,
                  fontSize: 11.5,
                  color: _PillPalette.text,
                ),
              ),
            ),
            if (pass.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  '|',
                  style: TextStyle(
                    fontSize: 11,
                    color: _PillPalette.muted,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  _showPassword ? pass : '••••••',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _PillPalette.mono,
                    fontSize: 11.5,
                    color: _PillPalette.text,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHelpPill() {
    final expanded = deskAgentWindowMode.value == DeskAgentWindowMode.expanded;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setDeskAgentWindowMode(
        expanded ? DeskAgentWindowMode.compact : DeskAgentWindowMode.expanded,
      ),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _PillPalette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DeskAgentIcons.headphones(size: 14, color: _PillPalette.accent),
            const SizedBox(width: 4),
            const Text(
              'Hỗ trợ',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _PillPalette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Recent peers, shown under the connect bar while the ID field has focus.
  bool get _showRecentDropdown =>
      _remoteIdFocusNode.hasFocus && _peersLoader.peers.isNotEmpty;

  Widget _buildRecentDropdown() {
    final peers = _peersLoader.peers.take(4).toList();
    return Positioned(
      top: 80,
      left: 12,
      right: 12,
      child: Material(
        color: _WidgetPalette.card,
        borderRadius: BorderRadius.circular(8),
        elevation: 6,
        shadowColor: const Color(0x33000000),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _WidgetPalette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 2),
                child: Row(
                  children: [
                    const Text(
                      'Thiết bị gần đây',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: _WidgetPalette.muted,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _hiddenRecent.addAll(
                            _peersLoader.peers.map((p) => p.id),
                          );
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Text(
                          'Xóa',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: _WidgetPalette.orangeDark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final p in peers.where((p) => !_hiddenRecent.contains(p.id)))
                InkWell(
                  onTap: () {
                    _remoteIdController.id = p.id;
                    _remoteIdFocusNode.unfocus();
                    setState(() {});
                    _onConnect();
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      children: [
                        DeskAgentIcons.monitor(
                          size: 14,
                          color: _WidgetPalette.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p.alias.isNotEmpty
                                    ? p.alias
                                    : (p.hostname.isNotEmpty
                                        ? p.hostname
                                        : p.id),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _WidgetPalette.text,
                                ),
                              ),
                              Text(
                                formatID(p.id),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontFamily: _WidgetPalette.mono,
                                  fontSize: 10.5,
                                  color: _WidgetPalette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: _WidgetPalette.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          p.online ? 'Online' : 'Offline',
                          style: const TextStyle(
                            fontSize: 10,
                            color: _WidgetPalette.muted,
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
    );
  }

  /// Collapsed composer: tapping the row opens the chat (as in the mockup,
  /// where the input is only a placeholder until the window expands).
  Widget _buildComposer() {
    return InkWell(
      onTap: () => setDeskAgentWindowMode(DeskAgentWindowMode.expanded),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: _WidgetPalette.card,
          border: Border(top: BorderSide(color: _WidgetPalette.border)),
        ),
        child: Row(
          children: [
            DeskAgentIcons.paperclip(size: 15, color: _WidgetPalette.muted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Nhập nội dung yêu cầu... (Ctrl+V dán ảnh/video)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: _WidgetPalette.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_WidgetPalette.blue, _WidgetPalette.blueDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: DeskAgentIcons.send(size: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chat title bar with the collapse control (expanded mode only).
  Widget _buildChatHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _WidgetPalette.card,
        border: Border(
          top: BorderSide(color: _WidgetPalette.border.withOpacity(0.5)),
          bottom: BorderSide(color: _WidgetPalette.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: _WidgetPalette.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Hỗ trợ IT DeskAgent',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _WidgetPalette.text,
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                setDeskAgentWindowMode(DeskAgentWindowMode.compact),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DeskAgentIcons.chevronDown(
                    size: 14,
                    color: _WidgetPalette.muted,
                  ),
                  const SizedBox(width: 2),
                  const Text(
                    'Thu gọn',
                    style: TextStyle(
                      fontSize: 11,
                      color: _WidgetPalette.muted,
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

  /// Expanded body: the real Manager chat, or — when the window is not the
  /// docked widget — the classic device/recent list.
  Widget _buildChatBody(BuildContext context) {
    if (!_isDockedWidget) return _buildHomeTab(context);
    return const AiChatPage(embedded: true);
  }

  // --- HOME GRID ---
  Widget _buildHomeTab(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, serverModel, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            children: [
              _buildMyDeviceCard(context, serverModel),
              const SizedBox(height: 12),
              _buildRecentSessionsCard(context),
            ],
          );
        },
      ),
    );
  }

  /// Header 42px from `client-widget.html`: logo (opens settings), the
  /// ID | password pair in monospace, and the orange "Gửi IT" action.
  Widget _buildHeader(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, serverModel, _) {
          final myId = serverModel.serverId.text.trim();
          final myPass = serverModel.serverPasswd.text.trim();
          return GestureDetector(
            // The window is frameless in widget mode: dragging the header moves
            // it, the way the mockup's window behaves.
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(
              height: 42,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
              color: _WidgetPalette.bg,
              child: Row(
                children: [
                  _buildLogoButton(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRect(
                      child: _buildCredentialGroup(myId, myPass),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildSendItButton(myId, myPass),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 28px logo with the online dot; clicking it opens the settings tab.
  Widget _buildLogoButton() {
    return Tooltip(
      message: 'DeskAgent · Mở cài đặt',
      child: InkWell(
        onTap: DesktopTabPage.onAddSetting,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DeskAgentIcons.icon(DeskAgentIcons.logo, size: 28),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _WidgetPalette.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: _WidgetPalette.bg, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `1 030 636 720 | xdsmkj` — click either half to copy it.
  Widget _buildCredentialGroup(String myId, String myPass) {
    final idText = myId.isNotEmpty ? formatID(myId) : '--- --- ---';
    final passText = myPass.isNotEmpty
        ? (_showPassword ? myPass : '••••••')
        : '------';
    return Row(
      children: [
        Flexible(
          child: InkWell(
            onTap: () {
              if (myId.isEmpty) return;
              Clipboard.setData(ClipboardData(text: myId));
              showToast('Đã sao chép ID!');
            },
            child: Text(
              idText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: _WidgetPalette.mono,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: _WidgetPalette.text,
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '|',
            style: TextStyle(fontSize: 12, color: _WidgetPalette.muted),
          ),
        ),
        Flexible(
          child: InkWell(
            onTap: () {
              if (myPass.isEmpty) return;
              Clipboard.setData(ClipboardData(text: myPass));
              showToast('Đã sao chép mật khẩu!');
            },
            onLongPress: () => setState(() => _showPassword = !_showPassword),
            child: Text(
              passText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: _WidgetPalette.mono,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _WidgetPalette.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Orange "Gửi IT" pill: copies ID + password for the helpdesk.
  Widget _buildSendItButton(String myId, String myPass) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (myId.isEmpty) return;
        Clipboard.setData(ClipboardData(text: 'ID: $myId  |  Pass: $myPass'));
        showToast('Đã sao chép ID & Mật khẩu để gửi IT!');
      },
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_WidgetPalette.orange, _WidgetPalette.orangeDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DeskAgentIcons.send(size: 12, color: Colors.white),
            const SizedBox(width: 4),
            const Text(
              'Gửi IT',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 36px connect bar from the mockup: monitor glyph, monospace input, blue
  /// "Kết nối" pill and the connection-options menu.
  Widget _buildConnectBar(BuildContext context) {
    return Container(
      height: 36,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: _WidgetPalette.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _WidgetPalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          DeskAgentIcons.monitor(size: 15, color: _WidgetPalette.muted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _remoteIdController,
              focusNode: _remoteIdFocusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [IDTextInputFormatter()],
              style: const TextStyle(
                fontFamily: _WidgetPalette.mono,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _WidgetPalette.text,
              ),
              decoration: const InputDecoration(
                hintText: 'Nhập ID máy cần điều khiển...',
                hintStyle: TextStyle(
                  fontFamily: _WidgetPalette.mono,
                  fontSize: 12,
                  color: _WidgetPalette.muted,
                ),
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _onConnect(),
            ),
          ),
          if (_remoteIdController.text.isNotEmpty)
            InkWell(
              onTap: () => setState(() => _remoteIdController.clear()),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DeskAgentIcons.x(size: 13, color: _WidgetPalette.muted),
              ),
            ),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _onConnect,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_WidgetPalette.blue, _WidgetPalette.blueDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DeskAgentIcons.zap(size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  const Text(
                    'Kết nối',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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

  // Card 1: My Device ID & Password
  Widget _buildMyDeviceCard(BuildContext context, ServerModel serverModel) {
    final theme = Theme.of(context);
    final myId = serverModel.serverId.text.trim();
    final myPass = serverModel.serverPasswd.text.trim();
    final isInstalled = bind.mainIsInstalled();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DeskAgentIcons.monitor(size: 16, color: _WidgetPalette.blue),
              const SizedBox(width: 6),
              Text(
                'THÔNG TIN MÁY NÀY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ID Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ID DeskAgent',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        myId.isNotEmpty ? formatID(myId) : '--- --- ---',
                        style: const TextStyle(
                          fontFamily: _WidgetPalette.mono,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: DeskAgentIcons.copy(size: 18),
                  tooltip: 'Sao chép ID',
                  splashRadius: 16,
                  onPressed: () {
                    if (myId.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: myId));
                      showToast(translate('Copied'));
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Password Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mật khẩu truy cập',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _showPassword
                            ? (myPass.isNotEmpty ? myPass : '------')
                            : '••••••••',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: _showPassword ? 1.0 : 2.0,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _showPassword
                      ? DeskAgentIcons.eyeOff(size: 18)
                      : DeskAgentIcons.eye(size: 18),
                  tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                  splashRadius: 16,
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
                IconButton(
                  icon: DeskAgentIcons.refresh(size: 18),
                  tooltip: 'Đổi mật khẩu tạm',
                  splashRadius: 16,
                  onPressed: () => bind.mainUpdateTemporaryPassword(),
                ),
                IconButton(
                  icon: DeskAgentIcons.pen(size: 18),
                  tooltip: 'Cài đặt mật khẩu',
                  splashRadius: 16,
                  onPressed: () =>
                      DesktopSettingPage.switch2page(SettingsTabKey.safety),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Big Copy All Button
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: MyTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: DeskAgentIcons.send(size: 16),
              label: const Text(
                'Sao chép ID & Mật khẩu gửi IT',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                if (myId.isNotEmpty) {
                  final text = 'ID: $myId  |  Pass: $myPass';
                  Clipboard.setData(ClipboardData(text: text));
                  showToast('Đã sao chép ID và Mật khẩu!');
                }
              },
            ),
          ),

          // Subtle UAC Banner (replaces the old giant pink box)
          if (Platform.isWindows && !isInstalled && !bind.isDisableInstallation())
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Cấp quyền Admin để hỗ trợ UAC',
                        style: TextStyle(fontSize: 11, color: Colors.amber),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        await rustDeskWinManager.closeAllSubWindows();
                        bind.mainGotoInstall();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          'Cài đặt',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                            decoration: TextDecoration.underline,
                          ),
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

  // Card 2: Remote Connection Input + Actions

  // Card 3: Recent Sessions / Quick Peers
  Widget _buildRecentSessionsCard(BuildContext context) {
    final theme = Theme.of(context);
    final peers = _peersLoader.peers;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DeskAgentIcons.history(size: 16, color: _WidgetPalette.orange),
              const SizedBox(width: 6),
              Text(
                'PHIÊN KẾT NỐI GẦN ĐÂY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
              const Spacer(),
              if (peers.isNotEmpty)
                InkWell(
                  onTap: () {
                    _peersLoader.getAllPeers();
                    setState(() {});
                  },
                  child: DeskAgentIcons.refresh(
                    size: 14,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    DeskAgentIcons.monitor(
                      size: 28,
                      color: theme.dividerColor.withOpacity(0.6),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Chưa có phiên kết nối gần đây',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: peers.take(4).map((p) {
                final displayName = p.alias.isNotEmpty
                    ? p.alias
                    : (p.hostname.isNotEmpty ? p.hostname : p.id);
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    _remoteIdController.id = p.id;
                    _onConnect();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                formatID(p.id),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                          splashRadius: 14,
                          onPressed: () {
                            _remoteIdController.id = p.id;
                            _onConnect();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
