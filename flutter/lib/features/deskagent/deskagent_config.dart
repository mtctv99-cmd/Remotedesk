// DeskAgent configuration constants for the Flutter side.
// Intentionally dependency-free (Dart core only) so any DeskAgent UI file
// can import it without pulling in extra packages.

/// Local option key toggling the DeskAgent widget mode: the main window
/// starts as a small always-on-top widget pinned to the bottom-right corner
/// of the primary screen. 'Y' (default) = widget mode, 'N' = the normal
/// centered window.
const String kOptionDeskAgentWidgetMode = 'deskagent-widget-mode';

/// Base URL of the local DeskAgent Manager service.
const String kManagerUrl = 'http://127.0.0.1:8080';

/// Base path of the Manager REST API, derived from [kManagerUrl].
const String kApiBase = '$kManagerUrl/api';
