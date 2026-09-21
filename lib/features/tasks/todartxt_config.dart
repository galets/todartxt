import 'dart:io';

import 'package:yaml/yaml.dart';

/// Default location of the todotxt YAML config on Linux:
/// `~/.config/todartxt.yaml` (respects `XDG_CONFIG_HOME`).
String todotxtConfigPath({String? homeDir, String? xdgConfigHome}) {
  final xdg = xdgConfigHome ?? Platform.environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/todartxt.yaml';
  final home = homeDir ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) return '$home/.config/todartxt.yaml';
  return '.config/todartxt.yaml';
}

/// Expand leading `~` to the home directory and `$VAR` / `${VAR}`
/// references using [env] (defaults to [Platform.environment]).
String expandTodoPath(String path, {String? homeDir, Map<String, String>? env}) {
  var out = path;
  final home = homeDir ?? Platform.environment['HOME'] ?? '';
  if (out == '~') {
    out = home;
  } else if (out.startsWith('~/') || out.startsWith('~\\')) {
    out = '$home${out.substring(1)}';
  }
  final environment = env ?? Platform.environment;
  out = out.replaceAllMapped(
    RegExp(r'\$(\w+)|\$\{([^}]+)\}'),
    (m) => environment[m.group(1) ?? m.group(2)] ?? m.group(0)!,
  );
  return out;
}

/// Extract the todo.txt location from parsed YAML.
///
/// Accepts `todo_file` (primary), `todo_path` and `path` aliases.
/// Values support `~` and `$VAR`/`${VAR}` expansion via [expandTodoPath].
String? todoPathFromYamlMap(Map<dynamic, dynamic> map,
    {String? homeDir, Map<String, String>? env}) {
  for (final key in const ['todo_file', 'todo_path', 'path']) {
    final v = map[key];
    if (v is String && v.isNotEmpty) {
      return expandTodoPath(v, homeDir: homeDir, env: env);
    }
  }
  return null;
}

/// Read the todo.txt path from an existing config file.
/// Returns null when missing/unparseable or when no known key is set.
Future<String?> readTodoPathFromConfigFile(String configPath,
    {String? homeDir, Map<String, String>? env}) async {
  try {
    final file = File(configPath);
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    final parsed = loadYaml(text);
    if (parsed is! Map) return null;
    return todoPathFromYamlMap(parsed as Map, homeDir: homeDir, env: env);
  } catch (_) {
    return null;
  }
}

/// Ensure `~/.config/todartxt.yaml` exists, creating it with [fallbackTodoPath]
/// as `todo_file:` when absent, then return the configured todo.txt path.
///
/// Previous Linux default ([fallbackTodoPath], e.g. `~/Tasks/todo.txt`) is
/// moved into the newly created file so existing behaviour is preserved.
Future<String> ensureTodotxtConfig({
  required String fallbackTodoPath,
  String? configPath,
  String? homeDir,
  String? xdgConfigHome,
  Map<String, String>? env,
}) async {
  final path = configPath ?? todotxtConfigPath(homeDir: homeDir, xdgConfigHome: xdgConfigHome);
  final existing = await readTodoPathFromConfigFile(path,
      homeDir: homeDir, env: env);
  if (existing != null) return existing;
  final file = File(path);
  if (!await file.exists()) {
    await file.parent.create(recursive: true);
    await file.writeAsString('todo_file: $fallbackTodoPath\n');
    return fallbackTodoPath;
  }
  // File exists but has no usable key: leave it untouched, use fallback.
  return fallbackTodoPath;
}
