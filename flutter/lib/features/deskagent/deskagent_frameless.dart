import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class _DeskAgentRect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

final class _DeskAgentPoint extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

/// Window-style surgery for the docked widget.
///
/// `window_manager.setAsFrameless()` alone leaves the caption bits in
/// `GWL_STYLE`, so Windows keeps clamping the window to the 136px minimum
/// track width (the pill is 86px wide). Removing the bits directly is what
/// the previous shipped build did; `WS_THICKFRAME` has to go too, otherwise
/// the DWM keeps a resize frame and the same minimum applies.
class DeskAgentFrameless {
  DeskAgentFrameless._();

  static const int _gwlStyle = -16;
  static const int _gwlExStyle = -20;
  static const int _wsCaption = 0x00C00000;
  static const int _wsSysMenu = 0x00080000;
  static const int _wsMinimizeBox = 0x00020000;
  static const int _wsMaximizeBox = 0x00010000;
  static const int _wsExNoActivate = 0x08000000;
  static const int _swpNoMove = 0x0002;
  static const int _swpNoSize = 0x0001;
  static const int _swpNoZOrder = 0x0004;
  static const int _swpNoActivate = 0x0010;
  static const int _swpFrameChanged = 0x0020;
  static const int _wdaNone = 0x00000000;
  static const int _wdaExcludeFromCapture = 0x00000011;

  /// Exclude window from screen capture (DXGI Desktop Duplication, BitBlt, Magnification).
  /// Supported on Windows 10 version 2004 (Build 19041) and newer.
  static bool setExcludeFromCapture(String windowTitle, {bool exclude = true}) {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final findWindowW = user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      final setWindowDisplayAffinity = user32.lookupFunction<
          Int32 Function(IntPtr, Uint32),
          int Function(int, int)>('SetWindowDisplayAffinity');

      final title = windowTitle.toNativeUtf16();
      final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = findWindowW(className, title);
      calloc.free(title);
      calloc.free(className);
      if (hwnd == 0) return false;

      final res = setWindowDisplayAffinity(
          hwnd, exclude ? _wdaExcludeFromCapture : _wdaNone);
      return res != 0;
    } catch (_) {
      return false;
    }
  }

  /// Ask DWM to render the native titlebar in dark mode (Win10 2004+ / Win11).
  static bool setDarkTitlebar(String windowTitle, {bool dark = true}) {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final dwmapi = DynamicLibrary.open('dwmapi.dll');
      final findWindowW = user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      final dwmSetWindowAttribute = dwmapi.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)>('DwmSetWindowAttribute');
      final title = windowTitle.toNativeUtf16();
      final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = findWindowW(className, title);
      calloc.free(title);
      calloc.free(className);
      if (hwnd == 0) return false;
      // DWMWA_USE_IMMERSIVE_DARK_MODE = 20 (19 on older Win10 builds).
      final value = calloc<Int32>()..value = dark ? 1 : 0;
      final attr = calloc<Uint32>()..value = 20;
      final res = dwmSetWindowAttribute(
          hwnd, attr.value, value.cast<Void>(), sizeOf<Int32>());
      calloc.free(value);
      calloc.free(attr);
      return res == 0;
    } catch (_) {
      return false;
    }
  }

  /// Move/resize the main window through Win32.
  ///
  /// The window_manager channel does not resize reliably once the caption
  /// bits are gone (the window collapses to the taskbar in tests), so the
  /// widget's size/anchor is applied here instead.
  static void setBounds(String windowTitle, int x, int y, int w, int h) {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final findWindowW = user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      final setWindowPos = user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
          int Function(int, int, int, int, int, int, int)>('SetWindowPos');
      final title = windowTitle.toNativeUtf16();
      final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = findWindowW(className, title);
      calloc.free(title);
      calloc.free(className);
      if (hwnd == 0) return;
      // HWND_TOPMOST (-1) keeps the widget above other windows.
      setWindowPos(hwnd, -1, x, y, w, h, _swpNoActivate);
    } catch (_) {
      // Fall back to the plugin path in the caller.
    }
  }

  /// True when the mouse pointer is more than [buffer] px outside the window
  /// [windowTitle]. Used by the auto-collapse watchdog: a blur can fire while
  /// the pointer is still over the card (e.g. right after a resize), so the
  /// decision is taken on the real cursor position.
  static bool isCursorOutsideWindow(String windowTitle, {int buffer = 6}) {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final findWindowW = user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      final getWindowRect = user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<_DeskAgentRect>),
          int Function(int, Pointer<_DeskAgentRect>)>('GetWindowRect');
      final getCursorPos = user32.lookupFunction<
          Int32 Function(Pointer<_DeskAgentPoint>),
          int Function(Pointer<_DeskAgentPoint>)>('GetCursorPos');

      final title = windowTitle.toNativeUtf16();
      final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = findWindowW(className, title);
      calloc.free(title);
      calloc.free(className);
      if (hwnd == 0) return false;

      final rect = calloc<_DeskAgentRect>();
      final point = calloc<_DeskAgentPoint>();
      getWindowRect(hwnd, rect);
      getCursorPos(point);
      final r = rect.ref;
      final p = point.ref;
      final outside = p.x < r.left - buffer ||
          p.x > r.right + buffer ||
          p.y < r.top - buffer ||
          p.y > r.bottom + buffer;
      calloc.free(rect);
      calloc.free(point);
      return outside;
    } catch (_) {
      return false;
    }
  }

  /// Strip the caption bits from the main window.
  static void apply(String windowTitle) {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final findWindowW = user32.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      final getWindowLongPtrW = user32.lookupFunction<
          IntPtr Function(IntPtr, Int32),
          int Function(int, int)>('GetWindowLongPtrW');
      final setWindowLongPtrW = user32.lookupFunction<
          IntPtr Function(IntPtr, Int32, IntPtr),
          int Function(int, int, int)>('SetWindowLongPtrW');
      final setWindowPos = user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
          int Function(int, int, int, int, int, int, int)>('SetWindowPos');

      final title = windowTitle.toNativeUtf16();
      final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
      final hwnd = findWindowW(className, title);
      calloc.free(title);
      calloc.free(className);
      if (hwnd == 0) return;

      final style = getWindowLongPtrW(hwnd, _gwlStyle);
      // Keep WS_THICKFRAME: removing it broke the Flutter surface (the window
      // rendered transparent). The caption bits alone are what enforce the
      // 136px minimum track width.
      final stripped =
          style & ~(_wsCaption | _wsSysMenu | _wsMinimizeBox | _wsMaximizeBox);
      setWindowLongPtrW(hwnd, _gwlStyle, stripped);
      // WS_EX_NOACTIVATE keeps the widget from ever taking focus, and the
      // click never reaches Flutter. The shipped pill did not have it.
      final exStyle = getWindowLongPtrW(hwnd, _gwlExStyle);
      final exStripped = exStyle & ~_wsExNoActivate;
      if (exStripped != exStyle) {
        setWindowLongPtrW(hwnd, _gwlExStyle, exStripped);
      }
      setWindowPos(
          hwnd,
          0,
          0,
          0,
          0,
          0,
          _swpNoMove |
              _swpNoSize |
              _swpNoZOrder |
              _swpNoActivate |
              _swpFrameChanged);
    } catch (_) {
      // Non-Windows or an unexpected API shape: keep the normal frame.
    }
  }
}
