import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

import 'about_info_page.dart';
import 'ai_chat_page.dart';
import 'event_viewer_page.dart';

const Color _kAccentColor = MyTheme.accent;

// DeskAgent home menu. Deliberately has no Scaffold of its own so it can be
// embedded directly as a pane child of DesktopSettingPage's PageView (like
// the _General/_About panes), while still being usable standalone: each item
// pushes a page that owns its own Scaffold.
class DeskAgentHomePage extends StatelessWidget {
  const DeskAgentHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _menuItem(
          context,
          Icons.info_outline,
          'About Info',
          'Host information collected on this machine',
          (_) => const AboutInfoPage(),
        ),
        _menuItem(
          context,
          Icons.event_note_outlined,
          'Event Viewer',
          'Recent Windows event log warnings and errors',
          (_) => const EventViewerPage(),
        ),
        _menuItem(
          context,
          Icons.chat_outlined,
          'AI Chat',
          'Chat with the AI bot or admin via the Manager',
          (_) => const AiChatPage(),
        ),
      ],
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    WidgetBuilder builder,
  ) {
    return ListTile(
      leading: Icon(icon, color: _kAccentColor),
      title: Text(translate(title)),
      subtitle: Text(translate(subtitle)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: builder),
      ),
    );
  }
}
