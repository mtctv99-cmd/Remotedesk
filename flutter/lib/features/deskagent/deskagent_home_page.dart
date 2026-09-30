import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

import 'about_info_page.dart';
import 'ai_chat_page.dart';
import 'deskagent_config.dart';
import 'event_viewer_page.dart';

const Color _kAccentColor = MyTheme.accent;

// DeskAgent home menu. Deliberately has no Scaffold of its own so it can be
// embedded directly as a pane child of DesktopSettingPage's PageView (like
// the _General/_About panes), while still being usable standalone: each card
// pushes a page that owns its own Scaffold.
class DeskAgentHomePage extends StatelessWidget {
  const DeskAgentHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(15),
      children: [
        _brandingHeader(context),
        const SizedBox(height: 12),
        _FeatureCard(
          icon: Icons.computer_outlined,
          iconColor: Colors.blue,
          title: 'System Info',
          subtitle: 'Host information collected on this machine',
          onTap: () => _open(context, (_) => const AboutInfoPage()),
        ),
        _FeatureCard(
          icon: Icons.event_note_outlined,
          iconColor: Colors.orange,
          title: 'Event Viewer',
          subtitle: 'Recent Windows event log warnings and errors',
          onTap: () => _open(context, (_) => const EventViewerPage()),
        ),
        _FeatureCard(
          icon: Icons.chat_outlined,
          iconColor: Colors.teal,
          title: 'AI Chat',
          subtitle: 'Chat with the AI bot or admin via the Manager',
          onTap: () => _open(context, (_) => const AiChatPage()),
        ),
        const _WidgetModeCard(),
      ],
    );
  }

  void _open(BuildContext context, WidgetBuilder builder) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: builder),
    );
  }

  // Branding header card: DeskAgent icon, name and a one-line description.
  Widget _brandingHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kAccentColor, _kAccentColor.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.support_agent,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DeskAgent',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  translate('Remote support toolkit for this machine'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// One tappable feature card with a tinted color icon and a hover lift effect.
class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureCard({
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovering ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_hovering ? 0.12 : 0.04),
                blurRadius: _hovering ? 12 : 6,
                offset: Offset(0, _hovering ? 4 : 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.iconColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          Icon(widget.icon, color: widget.iconColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            translate(widget.title),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            translate(widget.subtitle),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: _hovering ? _kAccentColor : theme.hintColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// DeskAgent widget mode switch: when ON the main window opens as a small
// always-on-top widget pinned to the bottom-right corner; when OFF it opens
// as the normal window. The change takes effect on the next app launch.
class _WidgetModeCard extends StatefulWidget {
  const _WidgetModeCard({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _WidgetModeCardState();
}

class _WidgetModeCardState extends State<_WidgetModeCard> {
  // Default is ON: only an explicit 'N' disables the widget mode.
  bool _enabled =
      bind.mainGetLocalOption(key: kOptionDeskAgentWidgetMode) != 'N';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kAccentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.picture_in_picture_alt,
                  color: _kAccentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translate('Widget góc dưới phải'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      translate('Áp dụng khi mở lại ứng dụng'),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: (v) async {
                  setState(() => _enabled = v);
                  // Persist as Y/N; 'N' restores the normal window.
                  await bind.mainSetLocalOption(
                    key: kOptionDeskAgentWidgetMode,
                    value: v ? 'Y' : 'N',
                  );
                  if (!v) {
                    // Clear the saved main window frame so the next normal
                    // (non-widget) launch centers the window again.
                    try {
                      await bind.setLocalFlutterOption(
                        k: '$windowFramePrefix${WindowType.Main.name}',
                        v: '',
                      );
                    } catch (e) {
                      debugPrint('failed to clear window frame: $e');
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
