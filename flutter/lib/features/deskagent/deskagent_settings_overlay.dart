import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Cửa sổ cài đặt của widget client — dựng theo client rollback v1.5.0+68
/// ("Cài đặt hệ thống" 380×620): HỆ THỐNG, MẬT KHẨU & QUYỀN TRUY CẬP,
/// MÁY CHỦ NỘI BỘ + footer Đóng · v0.1 · Lưu cài đặt.
///
/// Mọi tuỳ chọn gắn vào cơ chế thật (không mock):
/// - Khởi động cùng Windows: HKCU Run key `DeskAgent` (reg add/delete)
/// - Thu nhỏ vào khay: option `allow-hide-cm`
/// - Windows Service: `deskagent.exe --install` qua UAC
/// - Chỉ cho phép Admin IT: option `approve-mode` (click/password)
/// - keyboard / clipboard / audio: option `enable-*`
/// - Khóa Admin: đặt mật khẩu vĩnh viễn mainSetPermanentPasswordWithResult
class DeskAgentSettingsOverlay extends StatefulWidget {
  const DeskAgentSettingsOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<DeskAgentSettingsOverlay> createState() =>
      _DeskAgentSettingsOverlayState();
}

class _DeskAgentSettingsOverlayState extends State<DeskAgentSettingsOverlay> {
  // Bảng màu Win11 Fluent Dark của client rollback.
  static const Color bg = Color(0xFF181818);
  static const Color card = Color(0xFF222222);
  static const Color textMain = Color(0xFFF4F4F5);
  static const Color textSub = Color(0xFFA1A1AA);
  static const Color line = Color(0x14FFFFFF); // trắng 8%
  static const Color blue = Color(0xFF0E8FE8);
  static const Color blueSoft = Color(0xFF4CC2FF);
  static const Color amber = Color(0xFFFBBF24);

  bool _autostart = false;
  bool _serviceInstalled = false;
  bool _serviceBusy = false;
  bool _hideToTray = true;
  bool _adminOnly = true;
  bool _enableKeyboard = true;
  bool _enableClipboard = true;
  bool _enableAudio = false;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _adminOnly = bind.mainGetOptionSync(key: kOptionApproveMode) != 'click';
    _hideToTray = bind.mainGetOptionSync(key: 'allow-hide-cm') != 'N';
    _enableKeyboard = bind.mainGetOptionSync(key: kOptionEnableKeyboard) != 'N';
    _enableClipboard =
        bind.mainGetOptionSync(key: kOptionEnableClipboard) != 'N';
    _enableAudio = bind.mainGetOptionSync(key: kOptionEnableAudio) == 'Y';
    _serviceInstalled = bind.mainIsInstalled();
    _autostart = await _readAutostart();
    if (mounted) setState(() => _loading = false);
  }

  /// Trạng thái khởi động cùng Windows = наличие khóa Run `DeskAgent`.
  Future<bool> _readAutostart() async {
    try {
      final res = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        'DeskAgent',
      ]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Đặt trạng thái khởi động cùng Windows; true khi reg key thành công
  /// (trước kia exitCode bị bỏ qua — toggle lỗi vẫn báo "saved").
  Future<bool> _setAutostart(bool on) async {
    final exe = Platform.resolvedExecutable;
    final args = on
        ? [
            'add',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
            '/v',
            'DeskAgent',
            '/t',
            'REG_SZ',
            '/d',
            '"$exe"',
            '/f'
          ]
        : [
            'delete',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
            '/v',
            'DeskAgent',
            '/f'
          ];
    try {
      final res = await Process.run('reg', args);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Cài Windows Service qua UAC: bật `--install`, tắt `--uninstall`.
  /// exitCode != 0 (vd 1223) là người dùng HỦY bảng UAC — phải báo đúng
  /// thay vì dò lại isInstalled rồi toast sai kết quả.
  Future<void> _setService(bool on) async {
    setState(() => _serviceBusy = true);
    try {
      final exe = Platform.resolvedExecutable;
      final arg = on ? '--install' : '--uninstall';
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Start-Process -FilePath \'$exe\' -ArgumentList \'$arg\' -Verb RunAs -Wait',
      ]);
      if (res.exitCode != 0) {
        showToast('Yêu cầu quyền Administrator bị hủy — dịch vụ không thay đổi');
      } else {
        await Future.delayed(const Duration(seconds: 2));
        _serviceInstalled = bind.mainIsInstalled();
        if (mounted) setState(() {}); // cập nhật nhãn nút Bật/Tắt theo thật.
        showToast(on
            ? (_serviceInstalled
                ? 'Windows Service đã bật'
                : 'Windows Service chưa bật được')
            : (!_serviceInstalled
                ? 'Windows Service đã tắt'
                : 'Windows Service chưa tắt được'));
      }
    } catch (_) {
      showToast(translate('Failed'));
    }
    if (mounted) setState(() => _serviceBusy = false);
  }

  Future<void> _setAdminPassword() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: card,
        title: Text(translate('Set permanent password'),
            style: const TextStyle(fontSize: 15, color: textMain)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          style: const TextStyle(color: textMain),
          decoration: const InputDecoration(
            hintText: 'Nhập mật khẩu Admin…',
            hintStyle: TextStyle(color: textSub),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy bỏ')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xác nhận')),
        ],
      ),
    );
    final pass = controller.text;
    controller.dispose();
    if (ok != true || pass.isEmpty) return;
    if (pass.length < 6) {
      showToast('Mật khẩu Admin cần ít nhất 6 ký tự');
      return;
    }
    final success = await bind.mainSetPermanentPasswordWithResult(
        password: pass);
    showToast(success ? 'Đã đặt mật khẩu Admin' : translate('Failed'));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await bind.mainSetOption(
        key: 'allow-hide-cm', value: _hideToTray ? 'Y' : 'N');
    await bind.mainSetOption(
        key: kOptionApproveMode, value: _adminOnly ? 'password' : 'click');
    await bind.mainSetOption(
        key: kOptionEnableKeyboard, value: _enableKeyboard ? 'Y' : 'N');
    await bind.mainSetOption(
        key: kOptionEnableClipboard, value: _enableClipboard ? 'Y' : 'N');
    await bind.mainSetOption(
        key: kOptionEnableAudio, value: _enableAudio ? 'Y' : 'N');
    final autostartOk = await _setAutostart(_autostart);
    if (mounted) {
      showToast(autostartOk
          ? translate('Settings saved')
          : 'Đã lưu, nhưng đặt tự khởi động cùng Windows thất bại');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      child: _loading
          ? const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionHeader(
                            Icons.desktop_windows_outlined, 'Hệ thống'),
                        _sectionCard([
                          _toggleRow(
                              'Khởi động cùng Windows',
                              'Tự chạy ngầm khi mở máy tính',
                              _autostart,
                              (v) => setState(() => _autostart = v)),
                          _divider(),
                          _toggleRow(
                              'Thu nhỏ vào khay hệ thống (Tray)',
                              'Không tắt hẳn khi bấm đóng cửa sổ',
                              _hideToTray,
                              (v) => setState(() => _hideToTray = v)),
                          _divider(),
                          _serviceRow(),
                        ]),
                        _sectionHeader(
                            Icons.lock_outline, 'Mật khẩu & Quyền truy cập'),
                        _sectionCard([
                          _toggleRow(
                              'Chỉ cho phép Admin IT kết nối',
                              'Chỉ tài khoản công ty mới được điều khiển',
                              _adminOnly,
                              (v) => setState(() => _adminOnly = v)),
                          _divider(),
                          _toggleRow(
                              'Điều khiển bàn phím & chuột',
                              'Cho phép đối tác tương tác máy này',
                              _enableKeyboard,
                              (v) => setState(() => _enableKeyboard = v)),
                          _divider(),
                          _toggleRow(
                              'Đồng bộ Clipboard',
                              'Chia sẻ sao chép/dán giữa 2 máy',
                              _enableClipboard,
                              (v) => setState(() => _enableClipboard = v)),
                          _divider(),
                          _toggleRow(
                              'Truyền âm thanh máy tính',
                              'Phát âm thanh từ máy này sang đối tác',
                              _enableAudio,
                              (v) => setState(() => _enableAudio = v)),
                        ]),
                        _serverRow(),
                        _serverCard(),
                      ],
                    ),
                  ),
                ),
                _footer(),
              ],
            ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          const Icon(Icons.settings, size: 18, color: blueSoft),
          const SizedBox(width: 8),
          const Text('Cài đặt hệ thống',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: textMain)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: blueSoft.withOpacity(.1),
              border: Border.all(color: blueSoft.withOpacity(.3)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 11, color: blueSoft),
              SizedBox(width: 4),
              Text('About',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: blueSoft)),
            ]),
          ),
          const SizedBox(width: 6),
          InkResponse(
            onTap: widget.onClose,
            child: const Icon(Icons.close, size: 18, color: textSub),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: blueSoft),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: textMain)),
        ],
      ),
    );
  }

  Widget _sectionCard(List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: card,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  Widget _toggleRow(
      String title, String desc, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textMain)),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(fontSize: 10, color: textSub)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: value,
            activeColor: blue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _serviceRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Windows Service (Hỗ trợ UAC)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textMain)),
                const SizedBox(height: 2),
                const Text('Cho phép thao tác khi hiện bảng Admin UAC',
                    style: TextStyle(fontSize: 10, color: textSub)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _serviceBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _setService(!_serviceInstalled),
                  style: TextButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                  ),
                  child: Text(_serviceInstalled ? 'Tắt' : 'Bật',
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
        ],
      ),
    );
  }

  Widget _serverRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, size: 13, color: blueSoft),
          const SizedBox(width: 6),
          const Text('Máy chủ nội bộ (Mặc định)',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: textMain)),
          const Spacer(),
          InkWell(
            onTap: _setAdminPassword,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: amber.withOpacity(.12),
                border: Border.all(color: amber.withOpacity(.3)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(children: [
                Icon(Icons.lock_outline, size: 11, color: amber),
                SizedBox(width: 4),
                Text('Khóa Admin',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: amber)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serverCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: card,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text('Máy chủ đã cấu hình mặc định và được bảo vệ.',
          style: TextStyle(fontSize: 10.5, color: textSub)),
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Divider(height: 1, thickness: 1, color: line),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: card,
        border: Border(top: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          if (_saving)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
          TextButton(
            onPressed: widget.onClose,
            style: TextButton.styleFrom(
                foregroundColor: textSub,
                minimumSize: const Size(48, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: const Text('Đóng', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 10),
          const Text('v0.1', style: TextStyle(fontSize: 11, color: textSub)),
          const Spacer(),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: blueSoft,
              foregroundColor: const Color(0xFF0B0B0B),
              elevation: 0,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('Lưu cài đặt',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
