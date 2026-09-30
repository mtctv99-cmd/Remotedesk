import 'dart:async';
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

import 'about_info_page.dart';
import 'ai_chat_page.dart';
import 'event_viewer_page.dart';

/// Modern DeskAgent Home Widget tailored for the docked bottom-right client window.
/// Provides a sleek single-column card layout:
/// - My Device ID & Password (with 1-click copy for IT support)
/// - Remote Control (Connect input + actions)
/// - Recent Sessions
/// - Bottom Navigation Bar (Home, AI Chat, System Info, Event Logs)
class DeskAgentModernHome extends StatefulWidget {
  const DeskAgentModernHome({Key? key}) : super(key: key);

  @override
  State<DeskAgentModernHome> createState() => _DeskAgentModernHomeState();
}

class _DeskAgentModernHomeState extends State<DeskAgentModernHome> {
  int _currentIndex = 0;
  bool _showPassword = true;

  final IDTextEditingController _remoteIdController = IDTextEditingController();
  final FocusNode _remoteIdFocusNode = FocusNode();
  final AllPeersLoader _peersLoader = AllPeersLoader();

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _peersLoader.init(setState);
    _remoteIdFocusNode.addListener(() {
      if (_remoteIdFocusNode.hasFocus && _peersLoader.needLoad) {
        _peersLoader.getAllPeers();
      }
    });

    // Load last remote ID if available
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final lastId = await bind.mainGetLastRemoteId();
        if (lastId.isNotEmpty && _remoteIdController.id.isEmpty) {
          setState(() {
            _remoteIdController.id = lastId;
          });
        }
      } catch (_) {}
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHomeTab(context),
            const AiChatPage(embedded: true),
            const AboutInfoPage(embedded: true),
            const EventViewerPage(embedded: true),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // --- TAB 0: HOME ---
  Widget _buildHomeTab(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(
          child: ChangeNotifierProvider.value(
            value: gFFI.serverModel,
            child: Consumer<ServerModel>(
              builder: (context, serverModel, _) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  children: [
                    _buildMyDeviceCard(context, serverModel),
                    const SizedBox(height: 12),
                    _buildConnectCard(context),
                    const SizedBox(height: 12),
                    _buildRecentSessionsCard(context),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // Header: Logo + App Name + Hostname + Status + Settings Button
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final hostname = Platform.localHostname;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      color: theme.colorScheme.background,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [MyTheme.accent, MyTheme.accent.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'DeskAgent',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  hostname.isNotEmpty ? hostname : 'Local PC',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
          _buildOnlineStatusBadge(),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: translate('Settings'),
            splashRadius: 18,
            onPressed: DesktopTabPage.onAddSetting,
          ),
        ],
      ),
    );
  }

  // Connection status pill badge
  Widget _buildOnlineStatusBadge() {
    return Obx(() {
      final status = stateGlobal.svcStatus.value;
      Color dotColor;
      String label;

      if (status == SvcStatus.ready) {
        dotColor = const Color(0xFF32BEA6);
        label = 'Online';
      } else if (status == SvcStatus.connecting) {
        dotColor = Colors.amber;
        label = 'Connecting';
      } else {
        dotColor = const Color(0xFFE04F5F);
        label = 'Offline';
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: dotColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dotColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: dotColor,
              ),
            ),
          ],
        ),
      );
    });
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
              Icon(Icons.badge_outlined, size: 16, color: MyTheme.accent),
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
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          fontFamily: 'WorkSans',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
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
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                  splashRadius: 16,
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Đổi mật khẩu tạm',
                  splashRadius: 16,
                  onPressed: () => bind.mainUpdateTemporaryPassword(),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
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
              icon: const Icon(Icons.share_outlined, size: 16),
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
  Widget _buildConnectCard(BuildContext context) {
    final theme = Theme.of(context);

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
              Icon(Icons.desktop_windows_outlined, size: 16, color: Colors.teal),
              const SizedBox(width: 6),
              Text(
                'ĐIỀU KHIỂN MÁY TỪ XA',
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
          TextField(
            controller: _remoteIdController,
            focusNode: _remoteIdFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [IDTextInputFormatter()],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              fontFamily: 'WorkSans',
            ),
            decoration: InputDecoration(
              hintText: 'Nhập ID máy cần điều khiển...',
              hintStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: theme.hintColor.withOpacity(0.6),
              ),
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: MyTheme.accent, width: 1.5),
              ),
              suffixIcon: _remoteIdController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        setState(() {
                          _remoteIdController.clear();
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _onConnect(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text(
                      'Kết nối',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _onConnect(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: 'Tùy chọn kết nối',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onSelected: (val) {
                    if (val == 'file') _onConnect(isFileTransfer: true);
                    if (val == 'terminal') _onConnect(isTerminal: true);
                    if (val == 'camera') _onConnect(isViewCamera: true);
                    if (val == 'tcp') _onConnect(isTcpTunneling: true);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'file',
                      child: Row(
                        children: [
                          Icon(Icons.folder_shared_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Truyền File'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'terminal',
                      child: Row(
                        children: [
                          Icon(Icons.terminal_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Mở Terminal'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'camera',
                      child: Row(
                        children: [
                          Icon(Icons.camera_alt_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Xem Camera'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'tcp',
                      child: Row(
                        children: [
                          Icon(Icons.alt_route_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('TCP Tunneling'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
              Icon(Icons.history_rounded, size: 16, color: Colors.orange),
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
                  child: Icon(
                    Icons.refresh,
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
                    Icon(
                      Icons.devices_other_outlined,
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

  // --- BOTTOM NAVIGATION BAR ---
  Widget _buildBottomNav(BuildContext context) {
    final theme = Theme.of(context);

    final items = [
      _NavItem(Icons.home_rounded, Icons.home_outlined, 'Trang chủ'),
      _NavItem(Icons.support_agent_rounded, Icons.support_agent_outlined, 'Chat AI'),
      _NavItem(Icons.computer_rounded, Icons.computer_outlined, 'Cấu hình'),
      _NavItem(Icons.bug_report_rounded, Icons.bug_report_outlined, 'Bắt lỗi'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: List.generate(items.length, (idx) {
              final isSelected = _currentIndex == idx;
              final item = items[idx];
              final activeColor = MyTheme.accent;
              final inactiveColor =
                  theme.textTheme.bodySmall?.color?.withOpacity(0.5) ?? Colors.grey;

              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _currentIndex = idx),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        color: isSelected ? activeColor : inactiveColor,
                        size: 20,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? activeColor : inactiveColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData selectedIcon;
  final IconData icon;
  final String label;
  const _NavItem(this.selectedIcon, this.icon, this.label);
}
