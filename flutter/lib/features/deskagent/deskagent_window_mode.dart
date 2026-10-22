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
final Rx<DeskAgentWindowMode> deskAgentWindowMode = DeskAgentWindowMode.pill.obs;

/// Set once the window is up and the frameless style has been applied; before
/// that, stripping WS_CAPTION leaves the Flutter view attached to a surface
/// that never gets sized (the window renders white).
bool deskAgentWindowReady = false;

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
      if (isWindows && deskAgentWindowReady) {
        // Deterministic geometry: the plugin channel is unreliable on a
        // frameless window with the caption bits stripped.
        DeskAgentFrameless.setBounds(
          getWindowName(),
          x.round(),
          y.round(),
          size.width.round(),
          size.height.round(),
        );
      } else {
        await windowManager.setSize(size, ignoreDevicePixelRatio: true);
        await windowManager.setPosition(
          Offset(x, y),
          ignoreDevicePixelRatio: true,
        );
      }
    }
  } catch (e) {
    debugPrint('widget mode: failed to place the window: $e');
  }
  await windowManager.setAlwaysOnTop(true);
}

/// Logical size of the widget window for [mode] on a work area
/// [workAreaHeight] logical px tall.
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
