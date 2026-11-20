import 'package:logging/logging.dart';

enum IslandEditorLogLevel {
  off,
  error,
  warn,
  info,
  debug,
  all,
}

typedef IslandEditorLogHandler = void Function(String message);

/// Manages log service for [IslandEditor].
///
/// The editor is chatty at [IslandEditorLogLevel.debug] — every IME delta,
/// every rebuilt block, every transaction. Hosts forward `package:logging` to
/// their own console and file sinks at `Level.ALL`, so those calls used to
/// print on every keystroke. This is the gate: nothing leaves the library
/// unless the level below allows it, and the default is [off].
///
/// It never touches `Logger.root.level`: the host owns that logger, and an
/// editor that silenced the app's own logs would be worse than a noisy one.
class IslandLogConfiguration {
  IslandLogConfiguration._();

  factory IslandLogConfiguration() => _logConfiguration;

  static final IslandLogConfiguration _logConfiguration =
      IslandLogConfiguration._();

  IslandEditorLogHandler? handler;

  /// Verbosity. [IslandEditorLogLevel.off] keeps the editor silent, which is
  /// the default: a host that wants the editor's own records opts in.
  IslandEditorLogLevel level = IslandEditorLogLevel.off;

  /// Whether a record at [level] is within the configured verbosity.
  bool allows(IslandEditorLogLevel level) => level.index <= this.level.index;
}

/// For logging message in IslandEditor
class IslandEditorLog {
  IslandEditorLog._({
    required this.name,
  });

  final String name;

  /// For logging message related to [IslandEditor].
  ///
  /// For example, uses the logger when registering plugins
  ///   or handling something related to [EditorState].
  static IslandEditorLog editor = IslandEditorLog._(name: 'editor');

  /// For logging message related to [IslandSelectionService].
  ///
  /// For example, uses the logger when updating or clearing selection.
  static IslandEditorLog selection = IslandEditorLog._(name: 'selection');

  /// For logging message related to [IslandKeyboardService].
  ///
  /// For example, uses the logger when processing shortcut events.
  static IslandEditorLog keyboard = IslandEditorLog._(name: 'keyboard');

  /// For logging messages related to input services.
  ///
  /// For example, uses the logger when processing text inputs.
  static IslandEditorLog input = IslandEditorLog._(name: 'input');

  /// For logging message related to [IslandScrollService].
  ///
  /// For example, uses the logger when processing scroll events.
  static IslandEditorLog scroll = IslandEditorLog._(name: 'scroll');

  /// For logging message related to [FloatingToolbar] or [MobileToolbar].
  ///
  /// For example, uses the logger when processing toolbar events.
  static IslandEditorLog toolbar = IslandEditorLog._(name: 'toolbar');

  /// For logging message related to UI.
  ///
  /// For example, uses the logger when building the widget.
  static IslandEditorLog ui = IslandEditorLog._(name: 'ui');

  void error(String message) => _log(Level.SEVERE, message);
  void warn(String message) => _log(Level.WARNING, message);
  void info(String message) => _log(Level.INFO, message);
  void debug(String message) => _log(Level.FINE, message);

  /// Drops the record before it reaches the host's sinks unless the editor's
  /// own level allows it. See [IslandLogConfiguration].
  void _log(Level level, String message) {
    final configuration = IslandLogConfiguration();
    if (!configuration.allows(level.toLogLevel())) return;
    // The host's `package:logging` listeners see the record at whatever level
    // they enabled; `handler` is for hosts that want this library's records
    // without sharing a root listener with the whole app.
    Logger(name).log(level, message);
    configuration.handler?.call(
      '[${level.toLogLevel().name}][$name]: ${DateTime.now()}: $message',
    );
  }
}

extension on IslandEditorLogLevel {
  String get name {
    switch (this) {
      case IslandEditorLogLevel.off:
        return 'OFF';
      case IslandEditorLogLevel.error:
        return 'ERROR';
      case IslandEditorLogLevel.warn:
        return 'WARN';
      case IslandEditorLogLevel.info:
        return 'INFO';
      case IslandEditorLogLevel.debug:
        return 'DEBUG';
      case IslandEditorLogLevel.all:
        return 'ALL';
    }
  }
}

extension on Level {
  IslandEditorLogLevel toLogLevel() {
    if (this == Level.SEVERE) {
      return IslandEditorLogLevel.error;
    } else if (this == Level.WARNING) {
      return IslandEditorLogLevel.warn;
    } else if (this == Level.INFO) {
      return IslandEditorLogLevel.info;
    } else if (this == Level.FINE) {
      return IslandEditorLogLevel.debug;
    }
    return IslandEditorLogLevel.off;
  }
}
