import 'dart:ui';

import 'package:flutter_hbb/features/deskagent/deskagent_window_mode.dart';
import 'package:flutter_test/flutter_test.dart';

// Sizes from approved client-widget-goc.html mockup (compact card 380x96).
void main() {
  test('compact is 380x96 regardless of work area', () {
    expect(
      widgetWindowSize(DeskAgentWindowMode.compact, 1040),
      const Size(380, 96),
    );
  });

  test('expanded spans 1/2 of workAreaHeight', () {
    final s = widgetWindowSize(DeskAgentWindowMode.expanded, 1040);
    expect(s.width, 380);
    expect(s.height, 520);
  });
}
