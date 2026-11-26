import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons for the DeskAgent client surface.
///
/// The set is Lucide (ISC, https://lucide.dev), vendored under
/// `assets/icons/lucide/` so the build has no network dependency. Keeping one
/// helper means the stroke weight, size and colour stay consistent instead of
/// mixing stock Material glyphs with the design's outline icon language.
class DeskAgentIcons {
  DeskAgentIcons._();

  static const String _dir = 'assets/icons/lucide';

  /// Brand mark generated for DeskAgent (rounded app-icon artwork).
  static const String logo = 'assets/icons/deskagent_logo.png';

  /// The brand mark itself (not a Lucide glyph — `icon(logo)` would build the
  /// wrong asset path).
  static Widget brandLogo({double size = 28}) =>
      Image.asset(logo, width: size, height: size);

  /// The brand mark itself (not a Lucide glyph — `icon(logo)` would build the
  /// wrong asset path).
  static Widget brandLogo({double size = 28}) =>
      SvgPicture.asset(logo, width: size, height: size);

  /// One Lucide icon from the vendored set.
  static Widget icon(
    String name, {
    double size = 16,
    Color? color,
  }) {
    return SvgPicture.asset(
      '$_dir/$name.svg',
      width: size,
      height: size,
      colorFilter:
          color == null ? null : ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  static Widget monitor({double size = 16, Color? color}) =>
      icon('monitor', size: size, color: color);
  static Widget zap({double size = 16, Color? color}) =>
      icon('zap', size: size, color: color);
  static Widget settings({double size = 16, Color? color}) =>
      icon('settings', size: size, color: color);
  static Widget copy({double size = 16, Color? color}) =>
      icon('copy', size: size, color: color);
  static Widget send({double size = 16, Color? color}) =>
      icon('send', size: size, color: color);
  static Widget chevronUp({double size = 16, Color? color}) =>
      icon('chevron-up', size: size, color: color);
  static Widget chevronDown({double size = 16, Color? color}) =>
      icon('chevron-down', size: size, color: color);
  static Widget history({double size = 16, Color? color}) =>
      icon('history', size: size, color: color);
  static Widget x({double size = 16, Color? color}) =>
      icon('x', size: size, color: color);
  static Widget message({double size = 16, Color? color}) =>
      icon('message-square', size: size, color: color);
  static Widget shield({double size = 16, Color? color}) =>
      icon('shield-check', size: size, color: color);
  static Widget server({double size = 16, Color? color}) =>
      icon('server', size: size, color: color);
  static Widget info({double size = 16, Color? color}) =>
      icon('info', size: size, color: color);
  static Widget refresh({double size = 16, Color? color}) =>
      icon('refresh-cw', size: size, color: color);
  static Widget folder({double size = 16, Color? color}) =>
      icon('folder-open', size: size, color: color);
  static Widget terminal({double size = 16, Color? color}) =>
      icon('terminal', size: size, color: color);
  static Widget camera({double size = 16, Color? color}) =>
      icon('video', size: size, color: color);
  static Widget keyboard({double size = 16, Color? color}) =>
      icon('keyboard', size: size, color: color);
  static Widget clipboard({double size = 16, Color? color}) =>
      icon('clipboard', size: size, color: color);
  static Widget volume({double size = 16, Color? color}) =>
      icon('volume-2', size: size, color: color);
  static Widget rotate({double size = 16, Color? color}) =>
      icon('rotate-cw', size: size, color: color);
  static Widget lock({double size = 16, Color? color}) =>
      icon('lock', size: size, color: color);
  static Widget eyeOff({double size = 16, Color? color}) =>
      icon('eye-off', size: size, color: color);
  static Widget eye({double size = 16, Color? color}) =>
      icon('eye', size: size, color: color);
  static Widget pen({double size = 16, Color? color}) =>
      icon('pen-line', size: size, color: color);
  static Widget wifi({double size = 16, Color? color}) =>
      icon('wifi', size: size, color: color);
  static Widget check({double size = 16, Color? color}) =>
      icon('circle-check', size: size, color: color);
  static Widget warning({double size = 16, Color? color}) =>
      icon('triangle-alert', size: size, color: color);
  static Widget error({double size = 16, Color? color}) =>
      icon('circle-x', size: size, color: color);
  static Widget bell({double size = 16, Color? color}) =>
      icon('bell', size: size, color: color);
  static Widget cpu({double size = 16, Color? color}) =>
      icon('cpu', size: size, color: color);
  static Widget disk({double size = 16, Color? color}) =>
      icon('hard-drive', size: size, color: color);
  static Widget memory({double size = 16, Color? color}) =>
      icon('memory-stick', size: size, color: color);
  static Widget minimize({double size = 16, Color? color}) =>
      icon('minimize-2', size: size, color: color);
  static Widget maximize({double size = 16, Color? color}) =>
      icon('maximize-2', size: size, color: color);
  static Widget pin({double size = 16, Color? color}) =>
      icon('pin', size: size, color: color);
  static Widget power({double size = 16, Color? color}) =>
      icon('power', size: size, color: color);
  static Widget trash({double size = 16, Color? color}) =>
      icon('trash-2', size: size, color: color);
  static Widget user({double size = 16, Color? color}) =>
      icon('user', size: size, color: color);
  static Widget search({double size = 16, Color? color}) =>
      icon('search', size: size, color: color);
  static Widget paperclip({double size = 16, Color? color}) =>
      icon('paperclip', size: size, color: color);
  static Widget sparkles({double size = 16, Color? color}) =>
      icon('sparkles', size: size, color: color);
  static Widget headphones({double size = 16, Color? color}) =>
      icon('headphones', size: size, color: color);
  static Widget radio({double size = 16, Color? color}) =>
      icon('radio', size: size, color: color);
  static Widget bot({double size = 16, Color? color}) =>
      icon('bot', size: size, color: color);
  static Widget download({double size = 16, Color? color}) =>
      icon('download', size: size, color: color);
  static Widget external({double size = 16, Color? color}) =>
      icon('external-link', size: size, color: color);
}
