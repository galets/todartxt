import 'dart:io';

/// Log verbosity. Ordered low to high.
enum LogLevel { debug, info, warning, error }

/// Parse `log_level` value. Unknown/missing => [LogLevel.warning].
LogLevel parseLogLevel(Object? v) {
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warn':
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
    }
  }
  return LogLevel.warning;
}

/// Extract `log_level` from parsed YAML map.
LogLevel logLevelFromYamlMap(Map<dynamic, dynamic> map) =>
    parseLogLevel(map['log_level']);

/// Minimal stderr logger. Level set once at startup from config.
class AppLog {
  static LogLevel level = LogLevel.warning;

  /// Set level and always confirm on stderr (unfiltered),
  /// so users see logging works even at warning/error.
  static void init(LogLevel l) {
    level = l;
    stderr.writeln('[info] log_level=${l.name}');
  }

  static void log(LogLevel l, String msg) {
    if (l.index < level.index) {
      return;
    }

    stderr.writeln('[${l.name}] $msg');
  }

  static void debug(String m) => log(LogLevel.debug, m);

  static void info(String m) => log(LogLevel.info, m);

  static void warn(String m) => log(LogLevel.warning, m);

  static void err(String m) => log(LogLevel.error, m);
}
