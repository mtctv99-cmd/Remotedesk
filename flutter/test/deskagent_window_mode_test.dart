import 'dart:ui';

import 'package:flutter_hbb/features/deskagent/deskagent_window_mode.dart';
import 'package:flutter_test/flutter_test.dart';

// Sizes from the approved shipped widget (pill 86x40 -> panel 380x96).
void main() {
  test('pill is 86x40 regardless of work area', () {
    expect(
      widgetWindowSize(DeskAgentWindowMode.pill, 1040),
      const Size(86, 40),
    );
  });

  test('compact is 380x96 regardless of work area', () {
    expect(
      widgetWindowSize(DeskAgentWindowMode.compact, 1040),
      const Size(380, 96),
    );
  });

  test('expanded is 100vh-58, never below the pill height', () {
    final s = widgetWindowSize(DeskAgentWindowMode.expanded, 1040);
    expect(s.width, 380);
    expect(s.height, 1040 - 58);
    expect(widgetWindowSize(DeskAgentWindowMode.expanded, 1000).height, 942);
    // Tiny work areas fall back to the pill height.
    expect(widgetWindowSize(DeskAgentWindowMode.expanded, 60).height, 40);
  });
}
