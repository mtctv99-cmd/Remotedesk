import 'dart:async';
import 'dart:math';

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
const double _kWidgetCompactHeight = 96;
const double _kWidgetPillWidth = 86;
const double _kWidgetPillHeight = 40;
const double _kWidgetExpandedBottomGap = 58;
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
void wdTraceAppend(String msg) {
  if (!isDesktop) return;
  try {
    final t = DateTime.now();
    final stamp = '${t.hour.toString().padLeft(2, '0')}'
        ':${t.minute.toString().padLeft(2, '0')}'
        ':${t.second.toString().padLeft(2, '0')}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
    var entry = '$stamp $msg';
    final prev = bind.mainGetLocalOption(key: kDeskAgentTraceKey);
    if (prev.isNotEmpty) entry = '$prev | $entry';
    const cap = 2400;
    if (entry.length > cap) entry = entry.substring(entry.length - cap);
    bind.mainSetLocalOption(key: kDeskAgentTraceKey, value: entry);
  } catch (_) {
    // vết chỉ để debug; lỗi trace không được phá luồng UI.
  }
}

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
  deskAgentWindowMode.value = mode;
  if (isWindows && deskAgentWindowReady) {
    // The plugin's frameless flag alone leaves WS_CAPTION in GWL_STYLE, and
    // Windows then clamps the window to the 136px minimum track width.
    DeskAgentFrameless.apply(getWindowName());
  }
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  }
  try {
    final screens = await window_size.getScreenList();
    if (screens.isNotEmpty) {
      // On Windows the primary monitor is the one with origin (0, 0).
      final screen = screens.firstWhere(
        (s) => s.frame.left == 0 && s.frame.top == 0,
        orElse: () => screens.first,
      );
      final work = screen.visibleFrame; // physical px, excludes the taskbar
      // Repo convention (see _adjustRestoreMainWindowOffset in common.dart):
      // work in physical pixels and ignore the device pixel ratio.
      final scale = screen.scaleFactor <= 0 ? 1.0 : screen.scaleFactor;
      final logical = widgetWindowSize(mode, work.height / scale);
      final size = Size(logical.width * scale, logical.height * scale);
      final x = work.right - size.width - _kWidgetRightMargin;
      final y = work.bottom - size.height - _kWidgetBottomMargin;
      // The plugin channel is what tells the Flutter view its new size; a raw
      // SetWindowPos leaves the engine at the old surface size (black area).
      await windowManager.setSize(size, ignoreDevicePixelRatio: true);
      await windowManager.setPosition(
        Offset(x, y),
        ignoreDevicePixelRatio: true,
      );
    }
  } catch (e) {
    debugPrint('widget mode: failed to place the window: $e');
  }
  await windowManager.setAlwaysOnTop(true);
  // Ẩn khỏi taskbar — DeskAgent chỉ hiển thị icon ở khay hệ thống.
  if (isWindows) {
    await windowManager.setSkipTaskbar(true);
    // setSkipTaskbar ghi đè exstyle và khôi phục WS_EX_NOACTIVATE — bit này
    // khiến Flutter bỏ qua toàn bộ click, phải strip lại ngay.
    DeskAgentFrameless.apply(getWindowName());
    startNoActivateStripper();
  }
}

/// window_manager (setSkipTaskbar / setAsFrameless, hoặc main.dart) có thể
/// khôi phục WS_EX_NOACTIVATE một cách ASYNC sau khi mình strip — bit này
/// khiến Flutter bỏ qua toàn bộ click. Strip định kỳ 1 giây để bit không
/// bao giờ sống quá 1 giây.
Timer? _noActivateStripTimer;
void startNoActivateStripper() {
  if (!isWindows) return;
  _noActivateStripTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
    DeskAgentFrameless.apply(getWindowName());
  });
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
    DeskAgentWindowMode.expanded => workAreaHeight - _kWidgetExpandedBottomGap,
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
    final screens = await window_size.getScreenList();
    if (screens.isEmpty) return;
    final screen = screens.firstWhere(
      (s) => s.frame.left == 0 && s.frame.top == 0,
      orElse: () => screens.first,
    );
    final work = screen.visibleFrame; // physical px, excludes the taskbar
    final scale = screen.scaleFactor <= 0 ? 1.0 : screen.scaleFactor;
    final heightPx = max(logicalHeight, _kWidgetPillHeight) * scale;
    final widthPx = _kWidgetWidth * scale;
    final x = work.right - widthPx - _kWidgetRightMargin;
    final y = work.bottom - heightPx - _kWidgetBottomMargin;
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
  await windowManager.setAlwaysOnTop(true);
  if (isWindows) {
    await windowManager.setSkipTaskbar(true);
    DeskAgentFrameless.apply(getWindowName());
    startNoActivateStripper();
  }
}
