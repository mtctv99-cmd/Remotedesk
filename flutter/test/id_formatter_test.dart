import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats numeric IDs in groups of three', () {
    final f = IDTextInputFormatter();
    final out = f.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(
          text: '156371059', selection: TextSelection.collapsed(offset: 9)),
    );
    expect(out.text, '156 371 059');
  });

  test('keeps IPv4 input unchanged', () {
    final f = IDTextInputFormatter();
    const ip = '192.168.232.130';
    final out = f.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(
          text: ip, selection: TextSelection.collapsed(offset: 15)),
    );
    expect(out.text, ip);
  });

  test('controller id trims spaces for both ID and IP', () {
    final c = IDTextEditingController(text: '192.168.232.130');
    expect(c.id, '192.168.232.130');
    c.dispose();
  });
}
