// DeskAgent configuration constants for the Flutter side.
// Intentionally dependency-free (Dart core only) so any DeskAgent UI file
// can import it without pulling in extra packages.

/// Base URL of the local DeskAgent Manager service.
const String kManagerUrl = 'http://127.0.0.1:8080';

/// Base path of the Manager REST API, derived from [kManagerUrl].
const String kApiBase = '$kManagerUrl/api';
