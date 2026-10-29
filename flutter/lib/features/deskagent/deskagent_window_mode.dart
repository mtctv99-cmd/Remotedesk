import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_config.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_frameless.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

/// States of the docked DeskAgent widget. Sizes come from the approved
/// screenshot of the shipped build (`pill-old-click.png`):
///
/// - [pill]: the 86x40 "Hỗ trợ" pill at the bottom-right corner;
/// - [compact]: the 380x96 panel the pill expands into;
/// - [expanded]: the same panel followed by the IT chat.
enum DeskAgentWindowMode { pill, compact, expanded }

const double _kWidgetWidth = 380;
/// Panel sát nội dung: 2 hàng 32px + gap 6 + padding trên/dưới 10 = 90.
/// (Từng thử 18% chiều cao màn hình nhưng panel thành 154px toàn khoảng
/// trống — nội dung chỉ có 2 hàng.)
const double _kWidgetCompactHeight = 90;
const double _kWidgetPillWidth = 86;
const double _kWidgetPillHeight = 40;
const double _kWidgetRightMargin = 10;
const double _kWidgetBottomMargin = 6;

/// Current mode of the main widget window.
final Rx<DeskAgentWindowMode> deskAgentWindowMode =
    DeskAgentWindowMode.pill.obs;

/// Set once the window is up and the frameless style has been applied; before
/// that, stripping WS_CAPTION leaves the Flutter view attached to a surface
/// that never gets sized (the window renders white).
bool deskAgentWindowReady = false;

/// Option key của wd-trace (cùng một key với watchdog trong modern_home).
const String kDeskAgentTraceKey = 'wd-trace';

/// Ghi vết UI của widget vào option `wd-trace` — NỐI TIẾP thay vì ghi đè.
///
/// Nguyên nhân "panel tự ẩn" (phiên 16:34): key chỉ ghi đè một dòng nên
/// lịch sử mất, chỉ còn 'schedule(blur)' mà không biết path nào ẩn cửa sổ.
/// Nối tiếp + mốc giờ giúp tái hiện được chuỗi sự kiện; chuỗi có cap (~2KB)
/// nên toml không phình ra. Option persist xuyên process (DeskAgent_local
/// .toml), nên vết còn nhìn thấy từ nhiều lần khởi động trước.
///
/// Chỉ chạy trên build debug: mỗi lời gọi là một FFI đồng bộ (get) + một
/// (set) rồi `confy::store_path` ghi cả file toml, và hàm này được gọi cho
/// MỌI native event (blur, focus, move, đổi mode). Trên build release đó là
/// chi phí thuần trên UI thread không đổi lấy được thông tin gì.
final List<String> _wdTraceBuf = [];
bool _wdTraceScheduled = false;

void wdTraceAppend(String msg) {
  if (!isDesktop || !kDebugMode) return;
  final t = DateTime.now();
  final stamp = '${t.hour.toString().padLeft(2, '0')}'
      ':${t.minute.toString().padLeft(2, '0')}'
      ':${t.second.toString().padLeft(2, '0')}'
      '.${t.millisecond.toString().padLeft(3, '0')}';
  _wdTraceBuf.add('$stamp $msg');
  if (_wdTraceScheduled) return;
  // Gom các sự kiện trong cùng một nhịp rồi ghi đúng một lần: ghi từng event
  // nghĩa là mỗi blur/focus/move đều ghi file toml.
  _wdTraceScheduled = true;
  Timer(const Duration(milliseconds: 120), () {
    _wdTraceScheduled = false;
    final pending = _wdTraceBuf.join(' | ');
    _wdTraceBuf.clear();
    try {
      var entry = pending;
      final prev = bind.mainGetLocalOption(key: kDeskAgentTraceKey);
      if (prev.isNotEmpty) entry = '$prev | $entry';
      const cap = 2400;
      if (entry.length > cap) entry = entry.substring(entry.length - cap);
      bind.mainSetLocalOption(key: kDeskAgentTraceKey, value: entry);
    } catch (_) {
      // vết chỉ để debug; lỗi trace không được phá luồng UI.
    }
  });
}

/// true sau lần đầu áp topmost + ẩn taskbar (không đổi khi đổi mode).
bool _chromeApplied = false;

class _WorkArea {
  const _WorkArea(this.work, this.scale);
  final Rect work; // physical px
  final double scale;
}

_WorkArea? _workAreaCache;
DateTime _workAreaCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Vùng làm việc của màn hình chính.
///
/// `getScreenList()` đi qua kênh platform (JSON encode/decode) nên không gọi
/// ở mỗi frame; cache 2 giây để mở panel liên tiếp không trả giá round-trip,
/// nhưng vẫn bắt được đổi độ phân giải / scale / cắm-rút màn hình / taskbar
/// đổi độ cao. Cache vĩnh viễn (bản trước) làm widget lệch khỏi mép
/// phải-dưới suốt phiên sau khi màn hình thay đổi.
Future<_WorkArea> _workAreaGeometry() async {
  final cached = _workAreaCache;
  if (cached != null &&
      DateTime.now().difference(_workAreaCacheAt).inSeconds < 2) {
    return cached;
  }
  final screens = await window_size.getScreenList();
  _workAreaCacheAt = DateTime.now();
  if (screens.isEmpty) {
    return _workAreaCache = _WorkArea(
        const Rect.fromLTWH(0, 0, 1920, 1080), 1.0);
  }
  // On Windows the primary monitor is the one with origin (0, 0).
  final screen = screens.firstWhere(
    (s) => s.frame.left == 0 && s.frame.top == 0,
    orElse: () => screens.first,
  );
  return _workAreaCache = _WorkArea(
    screen.visibleFrame,
    screen.scaleFactor <= 0 ? 1.0 : screen.scaleFactor,
  );
}

/// Đóng: bật cờ để nội dung widget chạy hiệu ứng trượt sang phải, rồi chờ
/// xong mới resize cửa sổ. Nếu resize trước, phần trống của cửa sổ lộ nền
/// trắng vài frame và hiệu ứng không còn gì để trượt.
final RxBool deskAgentClosing = false.obs;

/// Áp hiệu ứng đóng trong [duration] rồi trả về. Do lớp UI đăng ký (xem
/// DeskAgentModernHome); null = không có UI, bỏ qua hiệu ứng.
Future<void> Function(Duration duration)? deskAgentClosingAnimation;

/// Apply [mode] to the main window: size first, then re-anchor the bottom-right
/// corner (a resize alone would keep the top-left corner in place).
/// No-op outside the docked widget window (widget mode off, other windows).
Future<void> setDeskAgentWindowMode(DeskAgentWindowMode mode) async {
  if (!isDesktop || desktopType != DesktopType.main) {
    return;
  }
  if (bind.mainGetLocalOption(key: kOptionDeskAgentWidgetMode) == 'N') {
    return;
  }
  // Mọi thay đổi mode (watchdog, menu, nút thu gọn, startup) đều qua đây —
  // điểm ghi vết duy nhất để trả lời "ai thu panel về pill".
  wdTraceAppend('mode→${mode.name}');
  // Đóng về pill: chạy hiệu ứng trượt-sang-phải TRƯỚC khi resize. Cửa sổ vẫn
  // giữ kích thước cũ trong lúc nội dung trượt đi, nên không có phần trống
  // nào lộ nền; resize sau đó không nhìn thấy vì màn hình đã trống.
  final toPill = mode == DeskAgentWindowMode.pill &&
      deskAgentWindowMode.value != DeskAgentWindowMode.pill;
  if (toPill) {
    final anim = deskAgentClosingAnimation;
    if (anim != null) {
      deskAgentClosing.value = true;
      try {
        await anim(const Duration(milliseconds: 170));
      } catch (_) {
        // Hiệu ứng không được phép chặn việc thu gọn.
      }
      deskAgentClosing.value = false;
    }
  }
  deskAgentWindowMode.value = mode;
  // KHÔNG gọi DeskAgentFrameless.apply ở đây nữa: nó là FFI đồng bộ (6 lần
  // lookup symbol + FindWindow + 2 Get/SetWindowLongPtr + SetWindowPos) chạy
  // trên UI thread mỗi lần đổi mode, mà style caption chỉ bị thêm lại bởi
  // setSkipTaskbar — thứ giờ chỉ chạy một lần.
  try {
    final geom = await _workAreaGeometry();
    final logical = widgetWindowSize(mode, geom.work.height / geom.scale);
    final size = Size(logical.width * geom.scale, logical.height * geom.scale);
    final x = geom.work.right - size.width - _kWidgetRightMargin * geom.scale;
    final y = geom.work.bottom - size.height - _kWidgetBottomMargin * geom.scale;
    // setSize (qua plugin channel) chứ không setBounds: setBounds đi thẳng
    // MoveWindow, không báo engine cấp lại surface, nên cửa sổ đổi kích thước
    // mà Flutter vẫn vẽ theo khung cũ (mở panel ra thì phần dưới trắng trơn).
    await windowManager.setSize(size, ignoreDevicePixelRatio: true);
    await windowManager.setPosition(
      Offset(x, y),
      ignoreDevicePixelRatio: true,
    );
  } catch (e) {
    debugPrint('widget mode: failed to place the window: $e');
  }
  // Topmost + ẩn taskbar chỉ cần áp một lần cho mỗi process: đổi qua lại
  // pill/panel không làm thay đổi hai thuộc tính này, gọi lại chỉ tốn hai
  // round-trip native trên đường mở panel.
  if (isWindows && !_chromeApplied) {
    _chromeApplied = true;
    unawaited(windowManager.setAlwaysOnTop(true));
    await windowManager.setSkipTaskbar(true);
    // setSkipTaskbar ghi đè exstyle và khôi phục WS_EX_NOACTIVATE — bit này
    // khiến Flutter bỏ qua toàn bộ click, phải strip lại ngay.
    DeskAgentFrameless.apply(getWindowName());
  }
}


/// Logical size of the widget window for [mode] on a work area
/// [workAreaHeight] logical px tall.
/// Toạ độ vật lý (góc trái-trên) đặt popup Recent: neo phải panel,
/// mở hướng LÊN trên panel — không chìm dưới mép màn hình, hết lệch DPI.
Future<Offset> recentPeersPopupAnchor(
    {required double popupWidth, required double popupHeight}) async {
  final screens = await window_size.getScreenList();
  if (screens.isEmpty) return const Offset(0, 0);
  final screen = screens.firstWhere(
    (s) => s.frame.left == 0 && s.frame.top == 0,
    orElse: () => screens.first,
  );
  final work = screen.visibleFrame; // physical px
  final scale = screen.scaleFactor <= 0 ? 1.0 : screen.scaleFactor;
  final panelW = _kWidgetWidth * scale;
  final panelH = _kWidgetCompactHeight * scale;
  final panelLeft = work.right - _kWidgetRightMargin * scale - panelW;
  final panelTop = work.bottom - panelH - _kWidgetBottomMargin * scale;
  final x = panelLeft + 12 * scale;
  final y = panelTop - popupHeight * scale - 2;
  // Màn hình quá thấp: đè lên panel thay vì tràn ra ngoài.
  final cy = y < work.top ? work.top : y;
  return Offset(x, cy);
}

Size widgetWindowSize(DeskAgentWindowMode mode, double workAreaHeight) {
  final height = switch (mode) {
    DeskAgentWindowMode.pill => _kWidgetPillHeight,
    DeskAgentWindowMode.compact => _kWidgetCompactHeight,
    // Chat chỉ chiếm một nửa màn hình: mở to hết cỡ che gần kín desktop và
    // người dùng mất chỗ làm việc bên cạnh.
    DeskAgentWindowMode.expanded => workAreaHeight / 2,
  };
  final width = switch (mode) {
    DeskAgentWindowMode.pill => _kWidgetPillWidth,
    _ => _kWidgetWidth,
  };
  return Size(width, max(height, _kWidgetPillHeight));
}

/// Resize the docked widget window to [logicalHeight] logical px tall, keeping
/// the width and the bottom-right anchoring of the mode layouts. The settings
/// overlay opens with this (taller than the compact panel) and restores the
/// mode size afterwards via [setDeskAgentWindowMode].
Future<void> resizeDeskAgentWidgetWindow(double logicalHeight) async {
  if (!isDesktop || desktopType != DesktopType.main) {
    return;
  }
  if (!isWindows || !deskAgentWindowReady) {
    return;
  }
  try {
    final geom = await _workAreaGeometry();
    final heightPx = max(logicalHeight, _kWidgetPillHeight) * geom.scale;
    final widthPx = _kWidgetWidth * geom.scale;
    final x = geom.work.right - widthPx - _kWidgetRightMargin * geom.scale;
    final y = geom.work.bottom - heightPx - _kWidgetBottomMargin * geom.scale;
    // setSize rồi setPosition, KHÔNG dùng setBounds: setBounds đi thẳng
    // MoveWindow và không báo Flutter engine cấp lại surface, nên cửa sổ to
    // ra mà Flutter vẫn chỉ vẽ 90px — phần còn lại là nền trắng của cửa sổ.
    await windowManager.setSize(
      Size(widthPx, heightPx),
      ignoreDevicePixelRatio: true,
    );
    await windowManager.setPosition(
      Offset(x, y),
      ignoreDevicePixelRatio: true,
    );
  } catch (e) {
    debugPrint('widget mode: settings resize failed: $e');
  }
  // Không gọi lại setAlwaysOnTop/setSkipTaskbar/apply ở đây: chúng đã áp một
  // lần trong setDeskAgentWindowMode. Gọi lại mỗi lần resize làm cửa sổ mất
  // focus (blur) và watchdog thu gọn panel ngay sau khi dropdown vừa hiện.
}
