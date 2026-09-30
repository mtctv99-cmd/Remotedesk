import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

const double _kLogoSize = 96;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _kAccentColor = MyTheme.accent;

// Duplicated on purpose from src/deskagent/system_info.rs (module A): the
// Flutter and Rust sides collect host info independently (no FFI) and must
// emit the same JSON shape {hostname, os, os_version, arch} as SystemInfo.
const String _kSystemInfoScript = r'''
$ErrorActionPreference = 'Stop'
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq 'AMD64') { $arch = 'x86_64' } elseif ($arch -eq 'ARM64') { $arch = 'aarch64' }
$osInfo = Get-CimInstance Win32_OperatingSystem
$info = [ordered]@{
  hostname = $env:COMPUTERNAME
  os = 'windows'
  os_version = $osInfo.Version
  arch = $arch
}
ConvertTo-Json -InputObject $info -Compress
''';

// Presentation-only metadata: which JSON keys belong to which info card.
// The collected JSON shape is fixed by _kSystemInfoScript; the Memory &
// Drives group stays hidden until such keys ever appear, and the specs light
// up automatically if the shape grows.
class _InfoGroupSpec {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> keys;
  const _InfoGroupSpec(this.title, this.icon, this.color, this.keys);
}

const List<_InfoGroupSpec> _kGroupSpecs = [
  _InfoGroupSpec('Operating System', Icons.desktop_windows_outlined,
      Colors.blue, ['hostname', 'os', 'os_version']),
  _InfoGroupSpec(
      'Hardware', Icons.memory_outlined, Colors.teal, ['arch', 'cpu', 'processor']),
  _InfoGroupSpec('Memory & Drives', Icons.storage_outlined, Colors.orange, [
    'memory',
    'total_memory',
    'ram',
    'disk',
    'disks',
    'drives',
    'storage',
  ]),
];

// Catch-all card for keys the specs above do not cover.
const _InfoGroupSpec _kOtherGroupSpec =
    _InfoGroupSpec('Other', Icons.info_outline, Colors.grey, []);

// Friendly labels for the well-known keys; unknown keys fall back to a
// prettified version of the raw key.
const Map<String, String> _kKeyLabels = {
  'hostname': 'Hostname',
  'os': 'OS',
  'os_version': 'OS version',
  'arch': 'Architecture',
};

// About-info page for DeskAgent: collects host info like the Rust client by
// running a PowerShell script with the same JSON shape as system_info.rs.
class AboutInfoPage extends StatefulWidget {
  const AboutInfoPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AboutInfoPageState();
}

class _AboutInfoPageState extends State<AboutInfoPage> {
  String? _info; // Raw JSON text produced by the PowerShell script.
  bool _loading = false;
  String? _error; // Process/parsing failure message.

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _load();
    }
  }

  // Runs the PowerShell script and stores the JSON output. Kept independent
  // from the Rust system_info.rs implementation by design (no FFI).
  Future<void> _load() async {
    if (!Platform.isWindows || _loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        _kSystemInfoScript,
      ]);
      if (!mounted) {
        return;
      }
      if (result.exitCode != 0) {
        setState(() {
          _error = result.stderr.toString().trim().isNotEmpty
              ? result.stderr.toString().trim()
              : 'powershell exited with code ${result.exitCode}';
          _loading = false;
        });
        return;
      }
      setState(() {
        _info = result.stdout.toString().trim();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translate('About')),
        actions: [
          // Refresh action: spinner replaces the button while loading.
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: translate('Refresh'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Guard: the PowerShell collection only works on Windows.
    if (!Platform.isWindows) {
      return const Center(child: Text('Windows only'));
    }
    return ListView(
      padding: const EdgeInsets.all(15),
      children: [
        Icon(
          Icons.desktop_windows,
          size: _kLogoSize,
          color: _kAccentColor,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'DeskAgent',
            style: TextStyle(
              fontSize: _kTitleFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Center(
          child: Text(
            translate('Host information collected on this machine'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _infoBody(),
      ],
    );
  }

  Widget _infoBody() {
    if (_error != null) {
      return Text(
        '${translate('Error')}: $_error',
        style: TextStyle(fontSize: _kContentFontSize, color: Colors.red),
      );
    }
    if (_loading && _info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_info == null || _info!.isEmpty) {
      return Text(
        translate('No data'),
        style: TextStyle(fontSize: _kContentFontSize),
      );
    }
    // Prefer grouped info cards when the output parses as JSON, otherwise
    // fall back to showing the raw JSON as selectable text.
    try {
      final decoded = jsonDecode(_info!);
      if (decoded is Map) {
        return _groupedInfo(decoded);
      }
    } catch (_) {}
    return SelectableText(
      _info!,
      style: TextStyle(fontSize: _kContentFontSize, fontFamily: 'monospace'),
    );
  }

  // Groups the decoded JSON entries into cards by _kGroupSpecs. Keys the
  // specs do not mention are still shown, in an "Other" card.
  Widget _groupedInfo(Map decoded) {
    final used = <String>{};
    final cards = <Widget>[];
    for (final spec in _kGroupSpecs) {
      final rows = <MapEntry<String, String>>[];
      for (final key in spec.keys) {
        if (decoded.containsKey(key)) {
          rows.add(MapEntry(key, '${decoded[key]}'));
          used.add(key);
        }
      }
      if (rows.isNotEmpty) {
        cards.add(_groupCard(spec, rows));
      }
    }
    final other = <MapEntry<String, String>>[];
    for (final key in decoded.keys) {
      final keyText = '$key';
      if (!used.contains(keyText)) {
        other.add(MapEntry(keyText, '${decoded[key]}'));
      }
    }
    if (other.isNotEmpty) {
      cards.add(_groupCard(_kOtherGroupSpec, other));
    }
    if (cards.isEmpty) {
      return Text(
        translate('No data'),
        style: TextStyle(fontSize: _kContentFontSize),
      );
    }
    return Column(children: cards);
  }

  Widget _groupCard(
      _InfoGroupSpec spec, List<MapEntry<String, String>> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: spec.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(spec.icon, size: 19, color: spec.color),
                ),
                const SizedBox(width: 10),
                Text(
                  translate(spec.title),
                  style: const TextStyle(
                    fontSize: _kContentFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _infoRow(rows[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(MapEntry<String, String> row) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_keyLabel(row.key)}:',
          style: TextStyle(
            fontSize: _kContentFontSize,
            fontWeight: FontWeight.bold,
            color: _kAccentColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            row.value,
            style: TextStyle(fontSize: _kContentFontSize),
          ),
        ),
      ],
    );
  }

  String _keyLabel(String key) {
    final known = _kKeyLabels[key];
    if (known != null) {
      return known;
    }
    if (key.isEmpty) {
      return key;
    }
    final spaced = key.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}
