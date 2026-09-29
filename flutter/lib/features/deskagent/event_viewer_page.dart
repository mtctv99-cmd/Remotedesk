import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

const double _kContentFontSize = 15;
const double _kLogFontSize = 13;
const Color _kAccentColor = MyTheme.accent;
const int _kMaxEvents = 50;
const String _kLogSystem = 'System';
const String _kLogApplication = 'Application';

// Event viewer page for DeskAgent: reads recent critical/error/warning events
// from the Windows event log via wevtutil.
class EventViewerPage extends StatefulWidget {
  const EventViewerPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _EventViewerPageState();
}

class _EventViewerPageState extends State<EventViewerPage> {
  String _source = _kLogSystem;
  String? _events; // Raw wevtutil text output.
  bool _loading = false;
  String? _error; // Process failure message (stderr).

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _load();
    }
  }

  // Builds the wevtutil query for the given source log. Level 1 = Critical,
  // 2 = Error, 3 = Warning; /rd:true reads newest first, /c: caps the count.
  List<String> _wevtutilArgs(String source) => [
        'qe',
        source,
        '/q:*[$source[(Level=1 or Level=2 or Level=3)]]',
        '/c:$_kMaxEvents',
        '/rd:true',
        '/f:text',
      ];

  Future<void> _load() async {
    if (!Platform.isWindows || _loading) {
      return;
    }
    final source = _source;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Process.run('wevtutil', _wevtutilArgs(source));
      if (!mounted) {
        return;
      }
      if (result.exitCode != 0) {
        setState(() {
          _error = result.stderr.toString().trim().isNotEmpty
              ? result.stderr.toString().trim()
              : 'wevtutil exited with code ${result.exitCode}';
          _loading = false;
        });
        return;
      }
      setState(() {
        _events = result.stdout.toString().trim();
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
        title: Text(translate('Event Viewer')),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Guard: wevtutil is only available on Windows.
    if (!Platform.isWindows) {
      return const Center(child: Text('Windows only'));
    }
    return Column(
      children: [
        _sourceSelector(),
        const Divider(height: 1),
        Expanded(child: _resultBody()),
      ],
    );
  }

  // System/Application source chooser.
  Widget _sourceSelector() {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 15),
          child: Text(
            '${translate('Source')}:',
            style: TextStyle(fontSize: _kContentFontSize),
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text(_kLogSystem),
                selected: _source == _kLogSystem,
                selectedColor: _kAccentColor,
                onSelected: (_) {
                  if (_source != _kLogSystem) {
                    setState(() => _source = _kLogSystem);
                    _load();
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text(_kLogApplication),
                selected: _source == _kLogApplication,
                selectedColor: _kAccentColor,
                onSelected: (_) {
                  if (_source != _kLogApplication) {
                    setState(() => _source = _kLogApplication);
                    _load();
                  }
                },
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: 15),
            child: SizedBox(
              width: 18,
              height: 18,
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
    );
  }

  Widget _resultBody() {
    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Text(
          '${translate('Error')}: $_error',
          style: TextStyle(fontSize: _kContentFontSize, color: Colors.red),
        ),
      );
    }
    if (_loading && _events == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_events == null || _events!.isEmpty) {
      return Center(
        child: Text(
          translate('No events'),
          style: TextStyle(fontSize: _kContentFontSize),
        ),
      );
    }
    // Monospace text for the wevtutil /f:text output.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(15),
      child: SelectableText(
        _events!,
        style: TextStyle(fontSize: _kLogFontSize, fontFamily: 'monospace'),
      ),
    );
  }
}
