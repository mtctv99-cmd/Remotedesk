import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

const double _kContentFontSize = 15;
const double _kLogFontSize = 13;
const Color _kAccentColor = MyTheme.accent;
const int _kMaxEvents = 50;
const String _kLogSystem = 'System';
const String _kLogApplication = 'Application';

// One event parsed out of the wevtutil /f:text output. The raw block text is
// kept so the client-side filter can match anything that was displayed.
class _EventEntry {
  final String source;
  final String date;
  final String eventId;
  final String level;
  final String description;
  final String raw;
  _EventEntry({
    required this.source,
    required this.date,
    required this.eventId,
    required this.level,
    required this.description,
    required this.raw,
  });
}

// Event viewer page for DeskAgent: reads recent critical/error/warning events
// from the Windows event log via wevtutil.
class EventViewerPage extends StatefulWidget {
  final bool embedded;
  const EventViewerPage({Key? key, this.embedded = false}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _EventViewerPageState();
}

class _EventViewerPageState extends State<EventViewerPage> {
  // Newer Windows builds prefix every event with an "Event[N]" header line;
  // classic output instead starts each event with a "Log Name:" line.
  static final RegExp _kEventHeaderRegex = RegExp(r'^Event\[\d+\]\s*$');
  // Header fields look like "  Source: Some-Provider" (label may contain
  // spaces, e.g. "Event ID", "User Name").
  static final RegExp _kFieldRegex =
      RegExp(r'^\s*([A-Za-z][A-Za-z0-9 _]{0,30}):\s?(.*)$');

  String _source = _kLogSystem;
  String? _events; // Raw wevtutil text output.
  bool _loading = false;
  String? _error; // Process failure message (stderr).
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _load();
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
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
        // wevtutil pads some values with NUL characters; strip them once so
        // both the parsed cards and the raw fallback view stay readable.
        _events = result.stdout.toString().replaceAll('\x00', '').trim();
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
        automaticallyImplyLeading: !widget.embedded,
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
        _filterField(),
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

  // Client-side text filter over the loaded events.
  Widget _filterField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
      child: TextField(
        controller: _filterController,
        onChanged: (value) => setState(() => _filterQuery = value),
        decoration: InputDecoration(
          hintText: translate('Filter events'),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _filterQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _filterController.clear();
                    setState(() => _filterQuery = '');
                  },
                  icon: const Icon(Icons.clear, size: 18),
                ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
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
    final events = _parseEvents(_events!);
    if (events.isEmpty) {
      // Unparseable output: fall back to the raw monospace text.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: SelectableText(
          _events!,
          style: TextStyle(fontSize: _kLogFontSize, fontFamily: 'monospace'),
        ),
      );
    }
    final query = _filterQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? events
        : events
            .where((event) => event.raw.toLowerCase().contains(query))
            .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          translate('No matching events'),
          style: TextStyle(fontSize: _kContentFontSize),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 15),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _eventCard(filtered[index]),
    );
  }

  // Splits the /f:text output into events. Handles both the "Event[N]"
  // header style (newer Windows builds) and the classic style that starts
  // each event with a "Log Name:" line. Returns an empty list when the
  // output does not look parseable so the caller can show the raw text.
  List<_EventEntry> _parseEvents(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final markerStarts = <int>[];
    final logNameStarts = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (_kEventHeaderRegex.hasMatch(line)) {
        markerStarts.add(i);
      } else if (line.toLowerCase().startsWith('log name:')) {
        logNameStarts.add(i);
      }
    }
    // Never mix the two styles: the marker style also contains "Log Name:"
    // lines inside each event, which would split events in half.
    final starts = markerStarts.isNotEmpty ? markerStarts : logNameStarts;
    if (starts.isEmpty) {
      return const <_EventEntry>[];
    }
    final events = <_EventEntry>[];
    for (var s = 0; s < starts.length; s++) {
      // In marker mode the "Event[N]" line itself is skipped; in the classic
      // mode the "Log Name:" line is the first field of the block.
      final begin = starts[s] + (markerStarts.isNotEmpty ? 1 : 0);
      final end = s + 1 < starts.length ? starts[s + 1] : lines.length;
      final entry = _parseEventBlock(lines.sublist(begin, end));
      if (entry != null) {
        events.add(entry);
      }
    }
    return events;
  }

  _EventEntry? _parseEventBlock(List<String> lines) {
    String? source;
    String? date;
    String? eventId;
    String? level;
    final description = <String>[];
    var inDescription = false;
    var sawField = false;
    for (final line in lines) {
      if (!inDescription) {
        final match = _kFieldRegex.firstMatch(line);
        if (match != null) {
          sawField = true;
          final label = match.group(1)!.trim().toLowerCase();
          final value = match.group(2)!.trim();
          if (label == 'description') {
            inDescription = true;
            if (value.isNotEmpty) {
              description.add(value);
            }
          } else if (label == 'source') {
            source ??= value;
          } else if (label == 'date') {
            date ??= value;
          } else if (label == 'event id') {
            eventId ??= value;
          } else if (label == 'level') {
            level ??= value;
          }
          continue;
        }
        // Non-field text before the Description label: formatting noise.
        continue;
      }
      // Everything after the Description label belongs to the description;
      // keep blank lines so multi-paragraph messages stay readable.
      description.add(line.trim());
    }
    if (!sawField && description.isEmpty) {
      return null;
    }
    final descriptionText = description.join('\n').trim();
    return _EventEntry(
      source: source ?? '',
      date: date ?? '',
      eventId: eventId ?? '',
      level: level ?? '',
      description: descriptionText,
      raw: lines.map((line) => line.trim()).where((line) => line.isNotEmpty).join('\n'),
    );
  }

  // Level colors: Error (and Critical) red, Warning orange, everything else
  // (Information/Verbose/unknown, incl. localized names) grey.
  Color _levelColor(String level) {
    switch (level.trim().toLowerCase()) {
      case 'error':
      case 'critical':
      case 'lỗi':
        return Colors.red;
      case 'warning':
      case 'cảnh báo':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _levelIcon(String level) {
    switch (level.trim().toLowerCase()) {
      case 'error':
      case 'critical':
      case 'lỗi':
        return Icons.error;
      case 'warning':
      case 'cảnh báo':
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_outline;
    }
  }

  Widget _eventCard(_EventEntry event) {
    final color = _levelColor(event.level);
    final levelLabel = event.level.isEmpty ? translate('Event') : event.level;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_levelIcon(event.level), size: 20, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.source.isEmpty
                            ? translate('Event')
                            : event.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (event.date.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          event.date,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    levelLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (event.description.isNotEmpty) ...[
            Divider(height: 1, color: Theme.of(context).dividerColor),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                event.description,
                style: TextStyle(fontSize: _kLogFontSize, height: 1.35),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
