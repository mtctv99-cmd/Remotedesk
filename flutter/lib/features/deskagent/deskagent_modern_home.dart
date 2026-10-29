import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show kPrimaryMouseButton, kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/autocomplete.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_settings_overlay.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

import 'ai_chat_page.dart';
import 'deskagent_config.dart';
import 'deskagent_frameless.dart';
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
  static const Color green = Color(0xFF34D399); // semantic success (bao-cao-ux)
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

/// Chừa khoảng dưới overlay cài đặt để không dính sát taskbar.
const double _settingsBottomGap = 8;

/// Sàn chiều cao overlay cài đặt (màn nhỏ vẫn đọc được các mục).
const double _settingsFallbackHeight = 620;

/// Chiều cao nội dung thật của overlay cài đặt: header + 3 nhóm + footer.
const double _settingsContentHeight = 648;

class _DeskAgentModernHomeState extends State<DeskAgentModernHome>
    with WindowListener {
  // Mật khẩu hiện thẳng: người dùng cần đọc để gửi IT, che bằng dấu chấm chỉ
  // khiến họ phải long-press. Long-press vẫn đổi được nếu muốn ẩn khi có
  // người khác nhìn màn hình.
  bool _showPassword = true;

  /// true trong lúc resize cửa sổ (dropdown): bỏ qua mọi yêu cầu thu gọn để
  /// blur do đổi kích thước không đóng panel.
  bool _suppressCollapse = false;

  /// Danh sách gợi ý đang mở. Giữ riêng khỏi `_remoteIdFocusNode.hasFocus`
  /// vì click vào một dòng làm TextField mất focus trước khi onTap chạy.
  bool _recentListOpen = false;

  /// true sau khi cửa sổ đã đạt chiều cao đủ chỗ cho danh sách. Dùng để chỉ
  /// bắt đầu animation hiện danh sách khi khung đã đúng — nếu hiện sớm, nó bị
  /// vẽ trong khung 90px và trông như bị cắt cụt rồi giật ra.
  bool _recentListShown = false;

  /// Trạng thái bấm/kéo của viên thuốc. Phải là field của State, không phải
  /// biến local trong `_buildPill`: `_statusTimer` gọi setState mỗi 3 giây,
  /// rebuild pill và tạo closure mới. Với biến local thì một nhịp setState
  /// chen giữa pointerDown và pointerUp xoá mất `downAt`, điều kiện mở panel
  /// không bao giờ đúng — đó là "bấm viên thuốc lúc được lúc không".
  Offset? _pillDownAt;
  bool _pillDragging = false;

  /// Hẹn đóng danh sách gợi ý khi ô ID mất focus. Hoãn 180ms để tap trên
  /// một dòng thiết bị kịp chạy trước khi dòng bị gỡ khỏi tree.
  Timer? _recentListCloseTimer;


  final IDTextEditingController _remoteIdController = IDTextEditingController();
  final FocusNode _remoteIdFocusNode = FocusNode();
  final AllPeersLoader _peersLoader = AllPeersLoader();

  /// Peers dismissed with "Xóa" in the recent dropdown (this session only).
  final Set<String> _hiddenRecent = <String>{};

  /// First non-loopback IPv4 of this machine, shown in the panel's IP chip.
  String _localIp = '';

  /// Chế độ hiển thị của chip: 0=IP, 1=ID, 2=Pass (nút ⇄ chuyển qua lại).
  int _chipMode = 0;

  /// Recent peers popup window (`Thiết bị gần đây`, 380×220 frameless).
  int? _recentPeersWindowId;

  /// Popup Recent đang HIỂN THỊ hay đã ẩn. hide() chỉ giấu cửa sổ (cửa sổ
  /// vẫn sống và getFrame() vẫn thành công) — nếu watchdog coi cửa sổ ẩn này
  /// là "popup alive" thì panel không bao giờ tự thu về pill nữa (bug A3).
  bool _recentPeersPopupVisible = false;

  /// Popup Recent đang trên đường mở (await anchor rồi createWindow). Trong
  /// khoảng đó cửa sổ popup chưa "alive" nhưng panel ĐANG bị mất focus vì
  /// popup lấy foreground — watchdog phải nhịn, nếu không panel thu về pill
  /// ngay khi user bấm vào ô ID.
  bool _recentPeersOpening = false;

  /// Generation chống popup mồ côi (A10): mỗi lần mở/ẩn tăng biến đếm; code
  /// async sau `await` chỉ nhận kết quả nếu generation còn nguyên.
  int _recentPeersPopupGen = 0;

  /// Mode pill (auto-collapse / menu "Thu gọn") phải đóng overlay cài đặt —
  /// logic này từng là phép gán state trong build (anti-pattern).
  Worker? _modeWorker;

  bool _showSettings = false;

  Timer? _statusTimer;
  bool _statusRefreshing = false;
  bool _deviceIdLoaded = false;

  @override
  void initState() {
    super.initState();
    // The widget-mode main window bypasses DesktopHomePage (whose full
    // cross-window handler never mounts), so this handler MUST carry both the
    // popup's connect flow and the minimal contract the remote-session
    // windows rely on — otherwise those kWindow* calls are swallowed.
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      // Sender (popup Recent) gửi JSON string qua args — decode thống nhất.
      // (DesktopHomePage's handler assumed raw Map; here both forms arrive.)
      if (call.method == kWindowConnect) {
        final raw = call.arguments;
        final map = raw is Map
            ? raw.cast<dynamic, dynamic>()
            : (raw is String
                ? (jsonDecode(raw) as Map).cast<dynamic, dynamic>()
                : <dynamic, dynamic>{});
        final id = '${map['id'] ?? ''}';
        final ctx = this.context;
        if (ctx.mounted && id.isNotEmpty) {
          await connect(
            ctx,
            id,
            isFileTransfer: map['isFileTransfer'] == true,
            isTerminal: map['isTerminal'] == true,
            isViewCamera: map['isViewCamera'] == true,
            isTcpTunneling: map['isTcpTunneling'] == true,
          );
          _hideRecentPeersPopup();
        }
        return null;
      }
      // (A8) Phần còn lại của hợp đồng cross-window: các cửa sổ phiên
      // (remote/file transfer/cm) gọi về main window qua cùng handler này.
      // DesktopHomePage không mount trong widget mode — chuyển tiếp tại đây
      // những method trung tính, không phụ thuộc tab của DesktopHomePage.
      switch (call.method) {
        case kWindowMainWindowOnTop:
          await windowOnTop(null);
          break;
        case kWindowRefreshCurrentUser:
          gFFI.userModel.refreshCurrentUser();
          break;
        case kWindowGetScreenList:
          return jsonEncode((await window_size.getScreenList())
              .map(_deskAgentScreenToMap)
              .toList());
        case kWindowActionRebuild:
          reloadCurrentWindow();
          break;
        case kWindowEventShow:
          final shownId =
              call.arguments is Map ? call.arguments['id'] as int? : null;
          if (shownId != null) {
            await rustDeskWinManager.registerActiveWindow(shownId);
          }
          break;
        case kWindowEventHide:
          final hiddenId =
              call.arguments is Map ? call.arguments['id'] as int? : null;
          if (hiddenId != null) {
            await rustDeskWinManager.unregisterActiveWindow(hiddenId);
          }
          break;
        case kWindowBumpMouse:
          // bumpMouse yêu cầu int non-null — parse an toàn khỏi dynamic args.
          final bumpArgs = call.arguments is Map
              ? call.arguments as Map
              : const <dynamic, dynamic>{};
          final dx = int.tryParse('${bumpArgs['dx']}') ?? 0;
          final dy = int.tryParse('${bumpArgs['dy']}') ?? 0;
          return RdPlatformChannel.instance.bumpMouse(dx: dx, dy: dy);
        case kWindowEventOpenMonitorSession:
          final rawArgs = call.arguments;
          final monArgs = rawArgs is String
              ? (jsonDecode(rawArgs) as Map).cast<String, dynamic>()
              : (rawArgs as Map?)?.cast<String, dynamic>();
          if (monArgs == null) break;
          await rustDeskWinManager.openMonitorSession(
            monArgs['window_id'] as int,
            monArgs['peer_id'] as String,
            monArgs['display'] as int,
            monArgs['display_count'] as int,
            parseParamScreenRect(monArgs),
            monArgs['window_type'] as int,
          );
          break;
        case kWindowEventRemoteWindowCoords:
          final windowId = int.tryParse('${call.arguments}');
          if (windowId != null) {
            return jsonEncode(
                await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
          }
          return null;
      }
    });
    // Mode pill (watchdog/menu thu gọn) đóng overlay cài đặt — trước đây là
    // phép gán trong build ("if (_showSettings) _showSettings = false;").
    _modeWorker =
        ever<DeskAgentWindowMode>(deskAgentWindowMode, _onModeChanged);
    _peersLoader.init(setState);
    _remoteIdFocusNode.addListener(() {
      if (_remoteIdFocusNode.hasFocus) {
        if (_peersLoader.needLoad) _peersLoader.getAllPeers();
        _recentListCloseTimer?.cancel();
        _recentListCloseTimer = null;
        // Mở danh sách: giữ bằng cờ riêng, không dựa vào hasFocus.
        if (!_recentListOpen) {
          setState(() => _recentListOpen = true);
        }
      } else {
        // Rời ô nhập → đóng danh sách sau 180ms. Hoãn để onTap của dòng
        // thiết bị kịp chạy: click vào dòng làm TextField mất focus TRƯỚC,
        // nếu đóng ngay thì dòng bị gỡ khỏi tree và tap rơi vào hư không.
        // Nhờ vậy bấm được dòng, mà bỏ đi không nhập nữa thì danh sách cũng
        // tự đóng — trước đây nó kẹt lại vì chỉ tắt khi chọn peer/Kết nối.
        if (_recentListOpen) {
          _recentListCloseTimer?.cancel();
          _recentListCloseTimer =
              Timer(const Duration(milliseconds: 180), () {
            if (!mounted) return;
            if (_remoteIdFocusNode.hasFocus) return;
            setState(() => _recentListOpen = false);
            _syncDropdownHeight();
          });
        }
      }
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncDropdownHeight();
      });
    });

    // Không điền sẵn ID phiên trước: người dùng thấy một dãy số trong ô nhập
    // sẽ tưởng đó là ID máy mình hoặc một lựa chọn có sẵn, rồi bấm Kết nối
    // nhầm. Ô nhập để trống và chỉ có placeholder.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadLocalIp();
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshStatus();
    });
    _refreshStatus();
    windowManager.addListener(this);
  }

  // --- Auto-collapse: rời chuột/mất focus 650ms → thu về pill (như client
  // rollback). Bỏ qua khi mở menu, cài đặt hoặc popup Recent.
  Timer? _collapseTimer;

  @override
  void onWindowBlur() => _scheduleAutoCollapse('blur');

  @override
  void onWindowFocus() {
    _wdTrace('focus: cancel');
    _cancelAutoCollapse();
  }

  /// Mọi native window event đều ghi vết (trừ move/resize — phát liên tục
  /// khi kéo/dời): nếu panel bị ẩn bởi một path KHÔNG thuộc watchdog, vết
  /// `win/hide` hoặc `win/close` ở đây sẽ chỉ đúng thủ phạm cho lần tái hiện.
  @override
  void onWindowEvent(String eventName) {
    if (eventName != 'move' &&
        eventName != 'resize' &&
        eventName != 'moved' &&
        eventName != 'resized') {
      _wdTrace('win/$eventName');
    }
    super.onWindowEvent(eventName);
  }

  void _onModeChanged(DeskAgentWindowMode mode) {
    if (!_showSettings || mode != DeskAgentWindowMode.pill) return;
    if (!mounted) return;
    setState(() => _showSettings = false);
  }

  void _cancelAutoCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = null;
  }

  /// Ghi vết — nối tiếp (giữ lịch sử) chứ không ghi đè; see
  /// [wdTraceAppend] in deskagent_window_mode.dart.
  void _wdTrace(String msg) => wdTraceAppend(msg);

  void _scheduleAutoCollapse(String via) {
    if (_suppressCollapse) {
      _wdTrace('suppress(' + via + ')');
      return;
    }
    _wdTrace('schedule(' + via + ')');
    if (!_isDockedWidget) return;
    if (deskAgentWindowMode.value == DeskAgentWindowMode.pill) return;
    if (_showSettings) return;
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(milliseconds: 650), () async {
      if (!mounted) return;
      if (_suppressCollapse) {
        _wdTrace('keep: resizing');
        return;
      }
      if (deskAgentWindowMode.value == DeskAgentWindowMode.pill) return;
      if (_showSettings) return;
      // Keep #1: đang gõ vào ô ID (dropdown gợi ý mở kèm) thì không thu gọn.
      if (_remoteIdFocusNode.hasFocus) {
        _wdTrace('keep: id focus');
        return;
      }
      // Keep #1a: dropdown gợi ý đang hiện — người dùng đang chọn thiết bị,
      // thu gọn lúc này làm mất danh sách ngay dưới con trỏ.
      if (_showRecentDropdown) {
        _wdTrace('keep: dropdown open');
        return;
      }
      // Keep #1b: popup đang trên đường mở (chưa kịp "alive" nhưng cửa sổ
      // chính vừa mất focus vì nó lấy foreground).
      if (_recentPeersOpening) {
        _wdTrace('keep: popup opening');
        return;
      }
      // Keep #2: popup Recent còn HIỂN THỊ (cửa sổ ẩn-zombie không tính).
      if (await _isRecentPeersPopupAlive()) {
        _wdTrace('keep: popup alive');
        return;
      }
      // Keep #3: con trỏ còn trong rect cửa sổ chính.
      if (!DeskAgentFrameless.isCursorOutsideWindow(getWindowName())) {
        _wdTrace('keep: cursor inside');
        return;
      }
      _wdTrace('collapse now');
      _hideRecentPeersPopup();
      setDeskAgentWindowMode(DeskAgentWindowMode.pill);
    });
  }

  /// Popup Recent chỉ coi là "còn sống" khi: id chưa stale, cửa sổ vẫn trả
  /// lời getFrame, và KHÔNG đang ẩn — cửa sổ ẩn còn sống từng khiến getFrame
  /// luôn thành công → panel không bao giờ tự thu về pill nữa (A3).
  Future<bool> _isRecentPeersPopupAlive() async {
    final id = _recentPeersWindowId;
    if (id == null || !_recentPeersPopupVisible) return false;
    try {
      await WindowController.fromWindowId(id).getFrame();
      return true;
    } catch (_) {
      _recentPeersWindowId = null;
      _recentPeersPopupVisible = false;
      return false;
    }
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
    windowManager.removeListener(this);
    _collapseTimer?.cancel();
    _recentListCloseTimer?.cancel();
    _modeWorker?.dispose();
    _modeWorker = null;
    DesktopMultiWindow.setMethodHandler(null);
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
    // Đóng danh sách gợi ý trước khi rời panel: cửa sổ chat mở ra sẽ che nó.
    if (_recentListOpen) {
      _recentListCloseTimer?.cancel();
      _recentListCloseTimer = null;
      setState(() => _recentListOpen = false);
    }
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

  /// Chiều cao mục tiêu cho overlay cài đặt: gần hết vùng làm việc (chừa
  /// _settingsBottomGap để không dính taskbar), không cố định 620px nữa vì
  /// nội dung dài hơn và người dùng phải cuộn.
  Future<double> _settingsHeight() async {
    try {
      final screens = await window_size.getScreenList();
      if (screens.isEmpty) return _settingsFallbackHeight;
      final screen = screens.firstWhere(
        (s) => s.frame.left == 0 && s.frame.top == 0,
        orElse: () => screens.first,
      );
      final scale = screen.scaleFactor <= 0 ? 1.0 : screen.scaleFactor;
      // visibleFrame là physical px; resizeDeskAgentWidgetWindow nhân scale
      // lần nữa nên phải trả về logical.
      final logical = screen.visibleFrame.height / scale;
      // Cao bằng NỘI DUNG (~620) chứ không kéo hết màn hình: mở full chiều
      // cao thì 2/3 dưới là khoảng trống đen. Màn thấp hơn nội dung thì mới
      // cắt bớt theo màn (khi đó nội dung tự co trong hiệu lực của nó).
      final wanted = _settingsContentHeight + _settingsBottomGap;
      return wanted < logical ? wanted : logical;
    } catch (_) {
      return _settingsFallbackHeight;
    }
  }

  /// Cài đặt: swap nội dung cửa sổ sang overlay; đóng thì trả lại kích thước
  /// của mode hiện tại.
  Future<void> _openSettings() async {
    _hideRecentPeersPopup();
    setState(() => _showSettings = true);
    // Cài đặt mở hết vùng làm việc (trừ lề): nội dung dài, để 620px thì phải
    // cuộn mới thấy hết các mục.
    await resizeDeskAgentWidgetWindow(await _settingsHeight());
  }

  Future<void> _closeSettings() async {
    setState(() => _showSettings = false);
    await setDeskAgentWindowMode(deskAgentWindowMode.value);
  }

  bool get _isDockedWidget =>
      isDesktop &&
      desktopType == DesktopType.main &&
      bind.mainGetLocalOption(key: kOptionDeskAgentWidgetMode) != 'N';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent so the rounded card (pill 20px / panel 12px) shows the
      // desktop at its corners, the way the shipped widget did.
      backgroundColor: Colors.transparent,
      body: Obx(() {
        final mode = deskAgentWindowMode.value;
        // Đồng bộ chiều cao cửa sổ với dropdown gợi ý sau khi khung đã dựng:
        // gọi trong build (không setState) nên an toàn, và chỉ resize khi
        // trạng thái thực sự đổi.
        // Panel giữ nguyên trong lúc đang thu về pill: animation scale cần
        // widget còn sống, đổi sang pill ngay thì nó biến mất tức thì.
        if (_isDockedWidget && mode == DeskAgentWindowMode.pill) {
          // Overlay cài đặt được đóng qua _onModeChanged (ever) — gán state
          // ngay trong build là anti-pattern và có thể tranh với setState.
          return _buildPill(context);
        }
        if (_isDockedWidget) {
          return _ClosingSlide(
            child: MouseRegion(
            onEnter: (_) {
              _wdTrace('pointer: enter, cancel');
              _cancelAutoCollapse();
            },
            onExit: (_) {
              // onExit bắn giả trong hai tình huống: (a) cửa sổ vừa resize
              // nên Flutter chưa cập nhật hit-test, (b) focus vào TextField
              // làm subtree đổi cấu trúc. Kiểm tra con trỏ thật sự ngoài
              // trước khi hẹn thu gọn, chậm 120ms để qua frame resize.
              Future.delayed(const Duration(milliseconds: 120), () {
                if (!mounted) return;
                if (!DeskAgentFrameless.isCursorOutsideWindow(
                    getWindowName())) {
                  _wdTrace('exit: cursor still inside, ignore');
                  return;
                }
                _scheduleAutoCollapse('exit');
              });
            },
            child: _showSettings
                ? DeskAgentSettingsOverlay(onClose: _closeSettings)
                : Stack(
                    // Stack phải phủ hết cửa sổ: dropdown neo ở top:92, nằm
                    // dưới panel 90px, và mặc định Stack co theo Column nên
                    // phần đó ngoài hộp hit-test (bấm không ăn).
                    fit: StackFit.expand,
                    children: [
                      // Column dồn lên trên, KHÔNG giãn: nếu để Column nhận
                      // hết chiều cao cửa sổ thì panel 90px nằm trên cùng còn
                      // phần dưới là khoảng trong suốt — cửa sổ đã nới cho
                      // dropdown sẽ lộ nền sáng ở đó. Chế độ expanded vẫn cần
                      // Expanded nên chỉ ép min ở compact.
                      Align(
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: mode == DeskAgentWindowMode.expanded
                              ? MainAxisSize.max
                              : MainAxisSize.min,
                          children: [
                            _buildPanel(context),
                            if (mode == DeskAgentWindowMode.expanded)
                              Expanded(child: _buildChatBody(context)),
                          ],
                        ),
                      ),
                      // Gợi ý thiết bị gần đây: dropdown Flutter thuần, KHÔNG
                      // mở cửa sổ riêng nữa. Bản cũ dùng
                      // DesktopMultiWindow.createWindow và làm cửa sổ chính
                      // deadlock (process còn 1 thread, mất cửa sổ) ngay khi
                      // ô ID lấy focus.
                      if (_showRecentDropdown &&
                          mode != DeskAgentWindowMode.expanded)
                        _buildRecentDropdown(),
                    ],
                  ),
            ),
          );
        }
        // Main window with widget mode off keeps the settings-style home.
        return _buildHomeTab(context);
      }),
    );
  }

  /// Show/create the recent-peers popup; its bottom sits 4px above the panel
  /// input row (window top = panel top - 170 for 220 height + 54 offset).
  ///
  /// Generation-guard (A10): cả hai chặng `await` (anchor, createWindow) đều
  /// có cửa sổ blur giữa chừng — nếu field đã mất focus hay đã có lần mở/ẩn
  /// mới hơn, popup vừa tạo bị đóng ngay thay vì trôi thành window mồ côi.
  Future<void> _openRecentPeersPopup() async {
    if (!_isDockedWidget || !isWindows) return;
    final gen = ++_recentPeersPopupGen;
    // Cờ "đang mở" giữ trong suốt hàm: mọi nhánh return đều phải clear qua
    // finally, nếu lọt thì watchdog nhịn thu gọn vĩnh viễn.
    _recentPeersOpening = true;
    try {
      await _openRecentPeersPopupInner(gen);
    } finally {
      _recentPeersOpening = false;
    }
  }

  Future<void> _openRecentPeersPopupInner(int gen) async {
    final peers = _peersLoader.peers
        .take(4)
        .map((p) => {
              'id': p.id,
              'name': p.alias.isNotEmpty
                  ? p.alias
                  : (p.hostname.isNotEmpty ? p.hostname : p.id),
              'online': p.online,
            })
        .toList();
    if (_recentPeersWindowId != null) {
      try {
        WindowController.fromWindowId(_recentPeersWindowId!).show();
      } catch (_) {
        // id stale (popup đã bị đóng bằng X ở lần trước): rơi xuống nhánh
        // tạo mới — thay vì bỏ lỡ nguyên lần mở này (hành vi cũ).
        _recentPeersWindowId = null;
      }
      if (_recentPeersWindowId != null) {
        _recentPeersPopupVisible = true;
        DesktopMultiWindow.invokeMethod(
          _recentPeersWindowId!,
          'recent-peers-refresh',
          jsonEncode({'peers': peers}),
        );
        _refocusMainAfterPopupShow();
        return;
      }
    }
    // Đặt popup theo toạ độ vật lý trên cùng màn hình, neo phải panel và
    // mở hướng LÊN trên panel — hết lỗi vị trí DPI lệch + chìm dưới mép màn.
    final anchor =
        await recentPeersPopupAnchor(popupWidth: 356, popupHeight: 200);
    if (gen != _recentPeersPopupGen || !_remoteIdFocusNode.hasFocus) {
      return; // blur/ẩn giữa chừng trước khi kịp tạo — không mở.
    }
    try {
      final ctl = await DesktopMultiWindow.createWindow(jsonEncode({
        'type': -2,
        'peers': peers,
        'left': anchor.dx,
        'top': anchor.dy,
      }));
      if (gen != _recentPeersPopupGen || !_remoteIdFocusNode.hasFocus) {
        // Popup mồ côi (field đã blur trong lúc createWindow chạy): thu hồi.
        try {
          ctl.close();
        } catch (_) {}
        return;
      }
      _recentPeersWindowId = ctl.windowId;
      _recentPeersPopupVisible = true;
      // Trả focus về ô ID để gõ tiếp không bị nuốt ký tự khi popup lấy
      // foreground (nguyên nhân "ký tự tự biến mất").
      _refocusMainAfterPopupShow();
    } catch (e) {
      debugPrint('recent popup: create failed: $e');
    }
  }

  /// Popup là cửa sổ chỉ-đọc (danh sách peers) nhưng native Show() vẫn
  /// SetForegroundWindow — đoạt OS focus khỏi main window (A1: ký tự gõ
  /// rơi vào popup mù). Child window show sau một nhịp engine, nên hồi phục
  /// trễ ~200ms và chỉ khi người dùng vẫn đang ở ô ID.
  void _refocusMainAfterPopupShow() {
    () async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (!_remoteIdFocusNode.hasFocus) return;
      try {
        await windowManager.focus();
        _remoteIdFocusNode.requestFocus();
      } catch (_) {}
    }();
  }

  /// Ẩn popup: giấu cửa sổ + đánh dấu KHÔNG còn hiển thị (cửa sổ ẩn-zombie
  /// không được tính "alive" trong watchdog), và tăng generation để một lần
  /// `_openRecentPeersPopup` đang bay biết mình đã bị hủy.
  void _hideRecentPeersPopup() {
    _recentPeersPopupGen++;
    _recentPeersPopupVisible = false;
    final id = _recentPeersWindowId;
    if (id == null) return;
    try {
      WindowController.fromWindowId(id).hide();
    } catch (_) {}
  }

  /// Pill 82x32 (radius 16) centered inside the 86x40 window. The Listener
  /// stays opaque over the full window so clicks never fall through the
  /// transparent 4/2px margins (design doc: budget 1+6.5+17+6.5+1).
  Widget _buildPill(BuildContext context) {
    void openMenu(Offset at) => _showPillMenu(context, at);
    return Center(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _pillDownAt = e.position;
          _pillDragging = false;
          if (e.buttons == kSecondaryMouseButton) {
            openMenu(e.position);
          }
        },
        onPointerMove: (e) {
          final d = _pillDownAt;
          if (d != null && !_pillDragging && e.buttons == kPrimaryMouseButton) {
            if ((e.position - d).distance > 6) {
              _pillDragging = true;
              windowManager.startDragging();
            }
          }
        },
        onPointerUp: (e) {
          final d = _pillDownAt;
          _pillDownAt = null;
          if (e.buttons == kSecondaryMouseButton) return;
          if (!_pillDragging && d != null && (e.position - d).distance <= 6) {
            setDeskAgentWindowMode(DeskAgentWindowMode.compact);
          }
        },
        child: Container(
          width: 82,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _PillPalette.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _PillPalette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
          value: 'panel',
          height: 34,
          onTap: () => setDeskAgentWindowMode(DeskAgentWindowMode.compact),
          child: Row(
            children: [
              DeskAgentIcons.maximize(size: 13, color: _PillPalette.text),
              const SizedBox(width: 8),
              const Text(
                'Mở panel',
                style: TextStyle(fontSize: 12, color: _PillPalette.text),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'hide',
          height: 34,
          onTap: () {
            _wdTrace('menu: pill → hide (chạy ngầm)');
            _hideRecentPeersPopup();
            windowManager.hide();
          },
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

  /// 380x96 panel the pill expands into (design doc):
  /// [monitor] [ID|pass|IP chip] [Gửi IT] [–] over [monitor] [ID input] [Kết nối].
  Widget _buildPanel(BuildContext context) {
    void openPanelMenu(Offset at) => _showPanelMenu(context, at);
    // Expanded: chat nối liền bên dưới nên chỉ bo góc trên; bo cả 4 góc sẽ
    // tạo khe hở giữa hai khối.
    final expanded = deskAgentWindowMode.value == DeskAgentWindowMode.expanded;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(expanded ? 0 : 12),
      bottomRight: Radius.circular(expanded ? 0 : 12),
    );
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onSecondaryTapUp: (d) => openPanelMenu(d.globalPosition),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          // Card panel phủ HẾT cửa sổ khi danh sách gợi ý mở: cửa sổ đã được
          // nới cao để chứa dropdown, nếu card chỉ cao 90 thì phần dưới là
          // vùng không widget nào vẽ — lộ nền trắng của cửa sổ Win32.
          height: _showRecentDropdown &&
                  deskAgentWindowMode.value == DeskAgentWindowMode.compact
              ? _recentWindowHeight
              : null,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _PillPalette.bg,
            borderRadius: radius,
            border: Border.all(color: _PillPalette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Tooltip(
                      message: 'Cài đặt',
                      child: InkWell(
                        onTap: _openSettings,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withOpacity(.15)),
                          ),
                          // Logo = monitor + bolt chồng nhau trong tile 32px.
                          // Monitor 15 (bằng icon nút Hỗ trợ) và bolt 9 đặt ở
                          // góc trên-trái của glyph monitor, không phải giữa
                          // tile — trước đây bolt 11px nằm đè ngang thân màn
                          // hình nên khối trông lệch.
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Center(
                                child: DeskAgentIcons.monitor(
                                    size: 15, color: const Color(0xFF38BDF8)),
                              ),
                              const Positioned(
                                left: 8.5,
                                top: 7.5,
                                child: Icon(Icons.bolt,
                                    size: 9, color: Color(0xFFF59E0B)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _buildIpChip()),
                    const SizedBox(width: 8),
                    ChangeNotifierProvider.value(
                      value: gFFI.serverModel,
                      child: Consumer<ServerModel>(
                        builder: (context, serverModel, _) {
                          final myId = serverModel.serverId.text.trim();
                          final myPass = serverModel.serverPasswd.text.trim();
                          return _buildHelpButton(myId, myPass);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // A14: GestureDetector gốc panel bắt pan toàn panel, kể cả
              // vùng ô nhập — gõ/bôi đen ID lại thành kéo cửa sổ. Detector
              // rỗng ở đây là thành viên "thắng" trong arena cho pan nên
              // nuốt drag của khu vực nhập; tap/chọn text không bị ảnh hưởng.
              GestureDetector(
                onPanStart: (_) {},
                child: Container(
                  height: 32,
                  // 1px cả hai phía: nút Kết nối (30px) lọt đều trong chip 32px.
                  padding: const EdgeInsets.only(left: 1, right: 1),
                  decoration: BoxDecoration(
                    color: _PillPalette.chip,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 7),
                      DeskAgentIcons.monitor(
                          size: 15, color: const Color(0xFFD4D4D8)),
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
                              fontSize: 12,
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
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _onConnect,
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            color: _PillPalette.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            // Căn giữa cả hai trục: icon và chữ Kết nối cao
                            // khác nhau (14 vs ~17px line-height) nên không có
                            // crossAxisAlignment thì chữ bị lệch xuống.
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              DeskAgentIcons.radio(
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 5),
                              const Text(
                                'Kết nối',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.0,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hàng 1: `[ID|IP] ⇄ │ Pass [mắt]` — chỉ IP/ID xoay vòng bằng ⇄, Pass
  /// luôn đứng riêng bên phải. Bấm giá trị để copy (Pass thì copy mật khẩu,
  /// kể cả khi đang ẩn).
  Widget _buildIpChip() {
    final rawId = gFFI.serverModel.serverId.text.trim();
    final pass = gFFI.serverModel.serverPasswd.text.trim();
    final idReady = rawId.isNotEmpty && !rawId.startsWith('Generating');
    final idShown = idReady ? formatID(rawId) : '---';
    final passSet = pass.isNotEmpty && pass != '-';

    // Hàng 1 dùng chung cỡ 12 cho cả IP và Pass: trước đó IP 11 / Pass 12 /
    // ô ID 13 làm ba khối trông ba cỡ khác nhau.
    final mono = const TextStyle(
        fontFamily: _PillPalette.mono,
        fontSize: 12,
        height: 1.0,
        color: _PillPalette.text);
    void copy(String text, String msg) {
      Clipboard.setData(ClipboardData(text: text));
      showToast(msg);
    }

    // Nửa trái: IP hoặc ID, đổi qua lại bằng ⇄.
    final showId = _chipMode == 1;
    final netValue = showId ? idShown : _localIp;
    final netCopyable = netValue.isNotEmpty && netValue != '---';

    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: _PillPalette.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // Không badge: chỉ giá trị, rộng cố định để ⇄ đứng yên khi đổi.
          SizedBox(
            width: 104,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: netCopyable
                  ? () => copy(
                      netValue, showId ? 'Đã sao chép ID!' : 'Đã sao chép IP!')
                  : null,
              child: Text(
                netValue.isEmpty ? '---' : netValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(
                    color:
                        netCopyable ? _PillPalette.text : _PillPalette.muted),
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _chipMode = showId ? 0 : 1),
            child: Tooltip(
              message: showId ? 'Hiện IP' : 'Hiện ID',
              child: SizedBox(
                width: 18,
                height: 22,
                child: Icon(Icons.swap_horiz,
                    size: 13, color: _PillPalette.muted),
              ),
            ),
          ),
          // Mật khẩu liền ngay sau ⇄ — một khối, không vạch ngăn, không nút
          // mắt. Bấm để copy; giữ chuột lâu để xem tạm chữ thật.
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: passSet ? () => copy(pass, 'Đã sao chép mật khẩu!') : null,
              onLongPress: passSet
                  ? () => setState(() => _showPassword = !_showPassword)
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      !passSet
                          ? 'không đặt'
                          : (_showPassword ? pass : '••••••'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Chữ thường thấp hơn chữ số cùng cỡ (x-height), nên
                      // Pass phải nhỉnh hơn để trông cân với IP phía trước.
                      style: mono.copyWith(
                          color: passSet
                              ? _PillPalette.text
                              : _PillPalette.muted),
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

  /// Badge + giá trị mono, bấm để copy (một phần của chip hàng 1).
  Widget _chipBadge(String label, String value, String copiedMsg) {
    return InkWell(
      onTap: value.isEmpty || value == '---'
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: value));
              showToast(copiedMsg);
            },
      onLongPress: label == 'Pass'
          ? () => setState(() => _showPassword = !_showPassword)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: _PillPalette.accent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: _PillPalette.accentText,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: _PillPalette.mono,
              fontSize: 12,
              color: _PillPalette.text,
            ),
          ),
        ],
      ),
    );
  }

  /// Nút `Hỗ trợ` rút gọn (icon-only) để nhường chỗ cho chip IP·ID·Pass.
  Widget _buildHelpButton(String myId, String myPass) {
    return Tooltip(
      message: 'Hỗ trợ — gửi ID & mật khẩu cho IT, mở chat',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (myId.isNotEmpty) {
            Clipboard.setData(
                ClipboardData(text: 'ID: $myId  |  Pass: $myPass'));
            showToast('Đã sao chép ID & Mật khẩu để gửi IT!');
          }
          setDeskAgentWindowMode(DeskAgentWindowMode.expanded);
        },
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF2B2B32),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(.07)),
          ),
          child: Center(
            child:
                DeskAgentIcons.headphones(size: 15, color: _PillPalette.accent),
          ),
        ),
      ),
    );
  }

  /// Menu chuột phải trên panel: thu về pill / đóng chạy ngầm (P0-3).
  void _showPanelMenu(BuildContext context, Offset at) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        overlay.size.width - at.dx,
        overlay.size.height - at.dy,
      ),
      color: _PillPalette.chip,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem<String>(
          value: 'collapse',
          height: 34,
          onTap: () {
            _wdTrace('menu: panel → pill');
            setDeskAgentWindowMode(DeskAgentWindowMode.pill);
          },
          child: const Row(
            children: [
              SizedBox(
                  width: 13,
                  child: Center(
                      child: Text('–',
                          style: TextStyle(
                              fontSize: 14, color: _PillPalette.muted)))),
              SizedBox(width: 8),
              Text('Thu gọn',
                  style: TextStyle(fontSize: 12, color: _PillPalette.text)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'hide',
          height: 34,
          onTap: () {
            _wdTrace('menu: panel → hide (chạy ngầm)');
            _hideRecentPeersPopup();
            windowManager.hide();
          },
          child: Row(
            children: [
              DeskAgentIcons.x(size: 13, color: _PillPalette.text),
              const SizedBox(width: 8),
              const Text('Đóng (Chạy ngầm)',
                  style: TextStyle(fontSize: 12, color: _PillPalette.text)),
            ],
          ),
        ),
      ],
    );
  }

  /// Recent peers, shown under the connect bar while the ID field has focus.
  bool get _showRecentDropdown =>
      _recentListOpen && _peersLoader.peers.isNotEmpty;

  /// Chiều cao cửa sổ khi danh sách gợi ý mở. `_kRecentDropdownTop` tính từ
  /// đỉnh cửa sổ (= đỉnh panel), nên công thức là: vị trí danh sách + số dòng
  /// thật (tối đa 3) + lề dưới. Dùng chung cho resize cửa sổ và chiều cao
  /// card panel để hai bên không lệch.
  double get _recentWindowHeight {
    final rows = _peersLoader.peers.length.clamp(1, _kRecentMaxRows);
    return _kRecentDropdownTop + rows * _kRecentRowHeight + 12;
  }

  /// Chiều cao khung danh sách gợi ý (không tính header). Cố định để cửa sổ
  /// không nhảy kích thước khi số thiết bị thay đổi; nhiều hơn thì cuộn.
  static const double _kRecentRowHeight = 28;
  /// Khoảng cách từ mép trên panel tới dropdown (dưới hàng nhập ID).
  /// Ngay dưới card panel (panel cao 90 + 6px khe), không đè lên hàng nhập.
  static const double _kRecentDropdownTop = 96;
  /// Panel compact chỉ 90px: dropdown nằm đè lên hai hàng, cần vừa trong
  /// khung nên tối đa 2 dòng hiển thị (phần còn lại cuộn).
  static const int _kRecentMaxRows = 3;

  /// Dropdown nằm gọn trong panel 90px nên không cần đổi kích thước cửa
  /// sổ. Mỗi lần resize đều làm Windows gửi blur (watchdog thu panel) và
  /// phần diện tích nới thêm chỉ là nền trống — cả hai đều là lỗi người
  /// dùng thấy rõ.
  /// Trạng thái nới cửa sổ hiện tại (chỉ resize khi nó đổi).
  bool _dropdownExpanded = false;

  /// Số thứ tự lời gọi _syncDropdownHeight. Listener focus gọi hàm này qua
  /// addPostFrameCallback ở MỖI lần focus/blur, nên các lời gọi chồng nhau:
  /// không có generation thì lời gọi cũ hết 250ms sẽ gán
  /// `_suppressCollapse = false` vào giữa lời gọi mới, mở cửa cho watchdog
  /// thu panel trong lúc dropdown đang hiện.
  int _syncDropdownGen = 0;

  Future<void> _syncDropdownHeight() async {
    if (!_isDockedWidget) return;
    if (deskAgentWindowMode.value != DeskAgentWindowMode.compact) {
      _syncDropdownGen++;
      _dropdownExpanded = false;
      return;
    }
    final want = _showRecentDropdown;
    final gen = ++_syncDropdownGen;
    _dropdownExpanded = want;
    _wdTrace('sync-dd: want=$want rows=${_peersLoader.peers.length}');
    // Watchdog nhịn trong lúc đổi kích thước: Windows gửi blur khi resize,
    // và nếu không chặn thì panel thu về pill ngay khi dropdown vừa hiện.
    _suppressCollapse = true;
    _cancelAutoCollapse();
    final panel =
        widgetWindowSize(DeskAgentWindowMode.compact, double.infinity).height;
    // Cùng nguồn với chiều cao card (_recentWindowHeight) để panel và cửa sổ
    // không bao giờ lệch nhau. So chiều cao thật của cửa sổ thay vì dựa cờ:
    // cờ có thể lệch khi blur/mode đổi chen vào, để lại cửa sổ dư khoảng trống
    // trắng phía dưới card.
    final target = want ? _recentWindowHeight : panel;
    try {
      final cur = await windowManager.getSize();
      if ((cur.height - target).abs() < 2) {
        // Đã đúng kích thước — chỉ cần mở khoá nếu đây là lời gọi mới nhất.
        if (gen == _syncDropdownGen && mounted) {
          _suppressCollapse = false;
          setState(() {});
        }
        return;
      }
    } catch (_) {}
    await resizeDeskAgentWidgetWindow(target);
    // Chờ cửa sổ đạt chiều cao mới thay vì ngủ 250ms mù: delay cứng làm
    // dropdown hiện muộn hơn mức cần, còn 250ms cố định thì lần nào cũng
    // khựng đúng chừng đó.
    if (want) {
      for (var i = 0; i < 12; i++) {
        await Future.delayed(const Duration(milliseconds: 16));
        if (gen != _syncDropdownGen || !mounted) return;
        try {
          final cur = await windowManager.getSize();
          if ((cur.height - target).abs() < 2) break;
        } catch (_) {
          break;
        }
      }
    }
    // Chỉ lời gọi mới nhất được mở khoá; lời gọi cũ đã bị thay thế thì im.
    if (gen != _syncDropdownGen || !mounted) return;
    _suppressCollapse = false;
    // Bật cờ hiện để dropdown chạy animation fade+slide của nó sau khi khung
    // đã đúng chiều cao — nếu hiện trước, nó bị vẽ trong khung 90px và bị cắt.
    setState(() => _recentListShown = want);
  }

  Widget _buildRecentDropdown() {
    final peers =
        _peersLoader.peers.where((p) => !_hiddenRecent.contains(p.id)).toList();
    // Cao đúng bằng số dòng (tối đa 3) + lề 2px trên/dưới, không để khung
    // trống khi chỉ có 1-2 thiết bị. Danh sách dài hơn thì cuộn.
    final rows = peers.length.clamp(1, _kRecentMaxRows);
    return Positioned(
      // Ngay dưới hàng nhập ID, không đè lên ô nhập.
      top: _kRecentDropdownTop,
      left: 12,
      right: 12,
      // Không bọc GestureDetector rỗng ở ngoài: nó cướp tap khỏi các dòng
      // con (tap arena chọn widget có handler gần nhất tính từ gốc), khiến
      // bấm vào thiết bị không làm gì.
      child: _RecentSlideIn(
        shown: _recentListShown,
        child: Material(
        color: _PillPalette.chip,
        borderRadius: BorderRadius.circular(8),
        child: Container(
        height: rows * _kRecentRowHeight + 4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _PillPalette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: peers.isEmpty
            ? Center(
                child: Text(
                  'Chưa có thiết bị',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _PillPalette.muted,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemExtent: _kRecentRowHeight,
                itemCount: peers.length,
                itemBuilder: (context, i) {
                  final p = peers[i];
                  // Mỗi dòng chỉ: tên máy (hoặc IP) và ID.
                  final name = p.alias.isNotEmpty
                      ? p.alias
                      : (p.hostname.isNotEmpty ? p.hostname : p.id);
                  // GestureDetector thay InkWell: dropdown nằm ngoài Material
                  // của panel nên ripple/ink không cần thiết, và GestureDetector
                  // nhận tap chắc chắn hơn khi bị Stack phủ.
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _wdTrace('recent: tap ${p.id}');
                      _remoteIdController.id = p.id;
                      _remoteIdFocusNode.unfocus();
                      setState(() => _recentListOpen = false);
                      _onConnect();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          DeskAgentIcons.monitor(
                            size: 14,
                            color: p.online
                                ? _PillPalette.accent
                                : _PillPalette.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _PillPalette.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatID(p.id),
                            style: const TextStyle(
                              fontFamily: _PillPalette.mono,
                              fontSize: 11,
                              color: _PillPalette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
            onTap: () => setDeskAgentWindowMode(DeskAgentWindowMode.compact),
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
    // Cùng card với panel phía trên: bo góc dưới, nền liền — không thì chat
    // nổi thành một khối vuông dính vào panel.
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _PillPalette.bg,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border(
            left: BorderSide(color: _PillPalette.border),
            right: BorderSide(color: _PillPalette.border),
            bottom: BorderSide(color: _PillPalette.border),
          ),
        ),
        child: const AiChatPage(embedded: true),
      ),
    );
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
    final passText =
        myPass.isNotEmpty ? (_showPassword ? myPass : '••••••') : '------';
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
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.6),
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
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.6),
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
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
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
          if (Platform.isWindows &&
              !isInstalled &&
              !bind.isDisableInstallation())
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined,
                        size: 16, color: Colors.amber),
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
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                        color:
                            theme.textTheme.bodySmall?.color?.withOpacity(0.6),
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios_rounded,
                              size: 12),
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

/// Dấu `|` ngăn cách hai phần của chip trên panel.
class _ChipSep extends StatelessWidget {
  const _ChipSep();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        '|',
        style: TextStyle(
          fontSize: 11,
          color: _PillPalette.muted.withOpacity(0.7),
        ),
      ),
    );
  }
}

/// Trả lời kWindowGetScreenList (A8): cùng hình dạng JSON với screenToMap
/// cục bộ trong desktop_home_page.dart — cửa sổ phiên parse phản hồi dựa
/// trên các khoá `frame`/`visibleFrame`/`scaleFactor`.
Map<String, dynamic> _deskAgentScreenToMap(window_size.Screen screen) => {
      'frame': {
        'l': screen.frame.left,
        't': screen.frame.top,
        'r': screen.frame.right,
        'b': screen.frame.bottom,
      },
      'visibleFrame': {
        'l': screen.visibleFrame.left,
        't': screen.visibleFrame.top,
        'r': screen.visibleFrame.right,
        'b': screen.visibleFrame.bottom,
      },
      'scaleFactor': screen.scaleFactor,
    };

/// Hiện danh sách gợi ý bằng fade + trượt lên 6px.
///
/// `shown` bật SAU khi cửa sổ đã đạt chiều cao đủ chỗ (xem
/// `_syncDropdownHeight`), nên animation không bao giờ chạy khi khung còn
/// 90px — trước đây khung nới ra rồi danh sách mới hiện đột ngột, cảm giác
/// khựng và như bị cắt.
class _RecentSlideIn extends StatelessWidget {
  const _RecentSlideIn({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: shown ? Offset.zero : const Offset(0, -0.04),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// Hiệu ứng đóng dùng chung cho mọi lần thu gọn: nội dung trượt sang phải
/// và mờ dần, giống notification trượt ra khỏi màn hình.
///
/// Chạy TRONG Flutter, trên cửa sổ vẫn giữ kích thước cũ — nhờ vậy không có
/// phần trống nào lộ nền, và cửa sổ chỉ resize sau khi nội dung đã trượt
/// khỏi khung. Animate cửa sổ bằng setBounds từng frame thì mỗi frame engine
/// phải cấp lại surface và nhìn rất giật.
class _ClosingSlide extends StatefulWidget {
  const _ClosingSlide({required this.child});

  final Widget child;

  @override
  State<_ClosingSlide> createState() => _ClosingSlideState();
}

class _ClosingSlideState extends State<_ClosingSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
  );

  @override
  void initState() {
    super.initState();
    deskAgentClosingAnimation = (d) async {
      if (mounted) _c.duration = d;
      // Chờ đúng thời lượng rồi trả về để setDeskAgentWindowMode resize tiếp.
      await _c.forward(from: 0).orCancel.catchError((_) {});
      if (mounted) _c.value = 0;
    };
  }

  @override
  void dispose() {
    deskAgentClosingAnimation = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInCubic.transform(_c.value);
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.centerRight,
            transform: Matrix4.identity()..translate(t * 60.0, 0.0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
