import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/features/deskagent/deskagent_config.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

/// Cửa sổ cài đặt của widget client — dựng theo mockup client-widget.html
/// ("CỬA SỔ CÀI ĐẶT"): CHẾ ĐỘ HIỂN THỊ (Sáng/Tối/Hệ thống), MẬT KHẨU & QUYỀN
/// TRUY CẬP, MÁY CHỦ NỘI BỘ và hàng nút Đóng / v0.1 / Lưu cài đặt.
///
/// Mọi tuỳ chọn gắn vào option thật (không mock):
/// - `theme`: local option + Get.changeThemeMode áp dụng ngay
/// - `allow-hide-cm`: thu nhỏ vào khay khi bấm đóng
/// - `approve-mode`: hỏi trước khi chấp nhận kết nối
/// - `enable-keyboard` / `enable-clipboard` / `enable-audio`: quyền phiên
/// - mật khẩu cố định: mainSetPermanentPasswordWithResult
class DeskAgentSettingsOverlay extends StatefulWidget {
  const DeskAgentSettingsOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<DeskAgentSettingsOverlay> createState() =>
      _DeskAgentSettingsOverlayState();
}

class _DeskAgentSettingsOverlayState extends State<DeskAgentSettingsOverlay> {
  static const Color bg = Color(0xFFF7F8FA);
  static const Color card = Colors.white;
  static const Color textMain = Color(0xFF111827);
  static const Color textSub = Color(0xFF6B7280);
  static const Color line = Color(0xFFE5E7EB);
  static const Color orange = Color(0xFFF97316);

  String _theme = 'light'; // light | dark | system
  bool _hideToTray = true;
  bool _askBeforeConnect = true; // approve-mode == 'click'
  bool _enableKeyboard = true;
  bool _enableClipboard = true;
  bool _enableAudio = false;
  bool _saving = false;
  bool _loading = true;
  bool _registered = false;
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _theme = bind.mainGetLocalOption(key: 'theme');
    if (_theme.isEmpty) _theme = 'light';
    _hideToTray = bind.mainGetOptionSync(key: 'allow-hide-cm') == 'Y';
    _askBeforeConnect =
        bind.mainGetOptionSync(key: kOptionApproveMode) != 'password';
    _enableKeyboard =
        bind.mainGetOptionSync(key: kOptionEnableKeyboard) != 'N';
    _enableClipboard =
        bind.mainGetOptionSync(key: kOptionEnableClipboard) != 'N';
    _enableAudio = bind.mainGetOptionSync(key: kOptionEnableAudio) == 'Y';
    _registered =
        bind.mainGetLocalOption(key: 'manager-device-token').isNotEmpty;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await bind.mainSetLocalOption(key: 'theme', value: _theme);
    await bind.mainSetOption(
        key: 'allow-hide-cm', value: _hideToTray ? 'Y' : 'N');
    await bind.mainSetOption(
        key: kOptionApproveMode, value: _askBeforeConnect ? 'click' : 'password');
    await bind.mainSetOption(
        key: kOptionEnableKeyboard, value: _enableKeyboard ? 'Y' : 'N');
    await bind.mainSetOption(
        key: kOptionEnableClipboard, value: _enableClipboard ? 'Y' : 'N');
    await bind.mainSetOption(
        key: kOptionEnableAudio, value: _enableAudio ? 'Y' : 'N');
    if (_passwordController.text.isNotEmpty) {
      final ok = await bind.mainSetPermanentPasswordWithResult(
          password: _passwordController.text);
      if (ok) {
        _passwordController.clear();
        showToast(translate('Settings saved'));
      } else {
        showToast(translate('Failed'));
      }
    } else {
      showToast(translate('Settings saved'));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('CHẾ ĐỘ HIỂN THỊ'),
                        _sectionCard([_themeSegment()]),
                        _sectionTitle('MẬT KHẨU & QUYỀN TRUY CẬP'),
                        _sectionCard(_permissionsRows()),
                        _sectionTitle('MÁY CHỦ NỘI BỘ'),
                        _sectionCard([
                          _settingRow(
                              'Máy chủ Manager',
                              kApiBase,
                              _registered
                                  ? _badge('Đã đăng ký', orange)
                                  : _badge('Chưa đăng ký', textSub)),
                        ]),
                        const SizedBox(height: 4),
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
      height: 44,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: const BoxDecoration(
        color: card,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.settings_outlined, size: 17, color: textSub),
          const SizedBox(width: 8),
          const Text(
            'Cài đặt',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: textMain),
          ),
          const Spacer(),
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: widget.onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: textSub),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: textSub),
      ),
    );
  }

  Widget _sectionCard(List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: card,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  Widget _settingRow(String title, String desc, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                    style: const TextStyle(fontSize: 10.5, color: textSub)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _themeSegment() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            _themeButton('Sáng', Icons.wb_sunny_outlined, 'light'),
            _themeButton('Tối', Icons.dark_mode_outlined, 'dark'),
            _themeButton('Hệ thống', Icons.computer_outlined, 'system'),
          ],
        ),
      ),
    );
  }

  Widget _themeButton(String label, IconData iconData, String mode) {
    final active = _theme == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _theme = mode);
          bind.mainSetLocalOption(key: 'theme', value: mode);
          if (mode == 'dark') {
            Get.changeThemeMode(ThemeMode.dark);
          } else if (mode == 'system') {
            Get.changeThemeMode(ThemeMode.system);
          } else {
            Get.changeThemeMode(ThemeMode.light);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: active ? orange : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, size: 14, color: active ? orange : textSub),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: active ? textMain : textSub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _permissionsRows() {
    return [
      _settingRow(
          'Hỏi trước khi chấp nhận kết nối',
          'Bật: mỗi phiên cần người dùng bấm xác nhận trên máy',
          Switch(
            value: _askBeforeConnect,
            activeColor: orange,
            onChanged: (v) => setState(() => _askBeforeConnect = v),
          )),
      _divider(),
      _settingRow(
          'Mật khẩu cố định',
          'Đặt mật khẩu truy cập vĩnh viễn cho máy này (bỏ trống để giữ nguyên)',
          const SizedBox.shrink()),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: TextField(
          controller: _passwordController,
          obscureText: true,
          style: const TextStyle(fontSize: 12, color: textMain),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Mật khẩu mới…',
            hintStyle: const TextStyle(fontSize: 11.5, color: textSub),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: orange),
            ),
          ),
        ),
      ),
      _divider(),
      _settingRow(
          'Điều khiển bàn phím & chuột',
          'Cho phép máy xa điều khiển bàn phím, chuột của máy này',
          Switch(
            value: _enableKeyboard,
            activeColor: orange,
            onChanged: (v) => setState(() => _enableKeyboard = v),
          )),
      _divider(),
      _settingRow('Đồng bộ Clipboard',
          'Cho phép trao đổi nội dung clipboard giữa hai máy',
          Switch(
            value: _enableClipboard,
            activeColor: orange,
            onChanged: (v) => setState(() => _enableClipboard = v),
          )),
      _divider(),
      _settingRow('Âm thanh máy tính',
          'Chuyển âm thanh của máy này sang máy xa khi kết nối',
          Switch(
            value: _enableAudio,
            activeColor: orange,
            onChanged: (v) => setState(() => _enableAudio = v),
          )),
    ];
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Divider(height: 1, thickness: 1, color: line),
    );
  }

  Widget _footer() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: card,
        border: Border(top: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: widget.onClose,
            style: TextButton.styleFrom(
                minimumSize: const Size(48, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            child:
                const Text('Đóng', style: TextStyle(fontSize: 12.5, color: textSub)),
          ),
          const SizedBox(width: 8),
          const Text('v0.1', style: TextStyle(fontSize: 11, color: textSub)),
          const Spacer(),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('Lưu cài đặt',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
