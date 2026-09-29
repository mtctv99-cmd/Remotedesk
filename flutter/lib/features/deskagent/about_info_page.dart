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
            style: TextStyle(fontSize: _kTitleFontSize),
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
    // Prefer key/value rows when the output parses as JSON, otherwise fall
    // back to showing the raw JSON as selectable text.
    try {
      final decoded = jsonDecode(_info!);
      if (decoded is Map) {
        return Column(
          children: [
            for (final entry in decoded.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key}:',
                      style: TextStyle(
                        fontSize: _kContentFontSize,
                        fontWeight: FontWeight.bold,
                        color: _kAccentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        '${entry.value}',
                        style: TextStyle(fontSize: _kContentFontSize),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      }
    } catch (_) {}
    return SelectableText(
      _info!,
      style: TextStyle(fontSize: _kContentFontSize, fontFamily: 'monospace'),
    );
  }
}
