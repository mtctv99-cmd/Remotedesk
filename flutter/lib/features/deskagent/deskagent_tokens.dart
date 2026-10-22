import 'package:flutter/material.dart';

/// Token màu + số đo dùng chung cho module DeskAgent.
/// Nguồn: `docs/CONTRACT_UI_DESIGN.md`, chép từ mockup HTML. Giá trị nào mockup
/// ghi TBD thì không có ở đây (không đoán).
abstract final class DeskAgentFluentColors {
  // ── Accent / overlay — popup-windows-goc.html:9-11, remote-session-goc.html:12 ──
  static const Color accent = Color(0xFF60CDFF);
  static const Color accentHover = Color(0xFF7CD5FF);
  static const Color accentGlow = Color.fromRGBO(96, 205, 255, 0.35);
  /// Overlay nút hover/active — remote-session-goc.html:16-17.
  static const Color hoverOverlay = Color.fromRGBO(255, 255, 255, 0.06);
  static const Color activeOverlay = Color.fromRGBO(255, 255, 255, 0.10);

  // ── Surface — popup-windows-goc.html:12-14, remote-session-goc.html:9-10,
  // contract §1.5 (acrylic + dialog đậm hơn), §4.1 (§4.4 body #181818) ──
  static const Color window = Color(0xFF202020);
  /// Acrylic BG `rgba(32,32,32,0.92)` + blur(24px) saturate(140%) — popup-windows-goc.html:336-337.
  static const Color acrylicSurface = Color.fromRGBO(32, 32, 32, 0.92);
  /// Dialog đậm hơn `rgba(30,30,30,0.96)` — popup-windows-goc.html:772.
  static const Color dialogSurface = Color.fromRGBO(30, 30, 30, 0.96);
  /// Nền body cửa sổ tools/chat popup — remote-session-goc.html:397-402, :1166-1174.
  static const Color deepSurface = Color(0xFF181818);
  static const Color card = Color(0xFF272727);
  static const Color surfaceSubtle = Color(0xFF2D2D2D);
  /// `--subtle` của remote session — remote-session-goc.html:10.
  static const Color subtle = Color(0xFF2B2B2B);

  // ── Trạng thái — popup-windows-goc.html:20-23, remote-session-goc.html:15 ──
  static const Color warning = Color(0xFFFBBF24);
  static const Color success = Color(0xFF34D399);
  static const Color danger = Color(0xFFF87171);
  static const Color dangerBg = Color.fromRGBO(248, 113, 113, 0.12);
  /// Nút close hover — remote-session-goc.html:15.
  static const Color closeHover = Color(0xFFC42B1C);

  // ── Text — popup-windows-goc.html:18-19, remote-session-goc.html:13-14 ──
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFA1A1AA);
  /// Text chính trên titlebar remote — remote-session-goc.html:13.
  static const Color titlebarText = Color(0xFFFFFFFF);
  /// Text phụ trên titlebar remote — remote-session-goc.html:14.
  static const Color titlebarTextSecondary = Color(0xFFD1D5DB);

  // ── Viền — contract §Lưu ý B: 8% cho remote/tools/chat popup, 12% cho dialog/toast/input ──
  /// `--win11-border` — remote-session-goc.html:11.
  static const Color border8 = Color.fromRGBO(255, 255, 255, 0.08);
  /// Viền chuẩn — popup-windows-goc.html:17.
  static const Color border12 = Color.fromRGBO(255, 255, 255, 0.12);
}

/// Bo góc / kích thước lặp lại. Nguồn ghi từng hằng số.
abstract final class DeskAgentMetrics {
  /// Titlebar remote — remote-session-goc.html:18.
  static const double titlebarHeight = 32;

  /// Dialog card — popup-windows-goc.html:774.
  static const double radiusDialog = 8;
  /// Card / surface, tool button — remote-session-goc.html:298-299, :157-183.
  static const double radiusCard = 8;
  /// Caption/tool/tab button — remote-session-goc.html:157-183, :341-346.
  static const double radiusButton = 4;
}
