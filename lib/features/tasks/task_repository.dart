import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:todo_txt/todo_txt.dart';

import 'todo_storage.dart';

/// Loads/saves tasks from the file supplied on the command line.
///
/// Wraps [TodoTxt] (stream-based load/save) so the UI stays decoupled and testable.
/// Persistence goes through a [TodoStorage] backend (plain file on
/// Linux/legacy, SAF document URI on Android slice 2).
class TaskRepository {
  String? _path;
  TodoStorage? _storage;
  List<Task> _tasks = [];
  final List<List<Task>> _history = [];

  String? get path => _path;
  TodoStorage? get storage => _storage;
  List<Task> get tasks => List.unmodifiable(_tasks);
  bool get canUndo => _history.isNotEmpty;
  bool _dirty = false;

  /// True when in-memory tasks differ from the loaded file.
  bool get isDirty => _dirty;

  /// Loads tasks from [path] via `TodoTxt.load`.
  ///
  /// Creates parent directories and an empty file when they are missing.
  Future<void> load(String path) async {
    await loadFromStorage(FileTodoStorage(path));
  }

  /// Loads tasks from an arbitrary [TodoStorage] backend (file or SAF).
  Future<void> loadFromStorage(TodoStorage storage) async {
    _storage = storage;
    _path = storage.displayName;
    _history.clear();
    _dirty = false;
    final text = await storage.readAll();
    final lines =
        Stream<String>.fromIterable(const LineSplitter().convert(text));
    _tasks = await TodoTxt.load(lines);
  }

  /// Persists current tasks back to the file used for loading.
  Future<void> save() async {
    final storage = _storage;
    if (storage == null) throw StateError('No file loaded');
    final buf = StringBuffer();
    for (final t in _tasks) {
      buf.writeln(t.toText());
    }
    await storage.writeAll(buf.toString());
    _dirty = false;
  }

  /// Saves only when there are unsaved changes (used for autosave on exit).
  Future<void> saveIfDirty() async {
    if (!_dirty) return;
    await save();
  }

  /// Re-reads the file from the current storage backend.
  ///
  /// Used when the app regains focus on Android so external edits are
  /// picked up. Any unsaved changes are flushed first via [saveIfDirty].
  Future<void> reload() async {
    final storage = _storage;
    if (storage == null) return;
    await saveIfDirty();
    await loadFromStorage(storage);
  }

  Future<void> toggleCompleted(int index) async {
    _ensureLoaded();
    _pushHistory();
    _tasks[index].completed = !_tasks[index].completed;
    _dirty = true;
    await save();
  }

  Future<void> add(Task task) async {
    _ensureLoaded();
    _pushHistory();
    _tasks.add(task);
    _dirty = true;
    await save();
  }

  Future<void> update(int index, Task task) async {
    _ensureLoaded();
    _pushHistory();
    _tasks[index] = task;
    _dirty = true;
    await save();
  }

  Future<void> removeAt(int index) async {
    _ensureLoaded();
    _pushHistory();
    _tasks.removeAt(index);
    _dirty = true;
    await save();
  }

  Future<void> undo() async {
    _ensureLoaded();
    if (_history.isEmpty) return;
    _tasks = _history.removeLast();
    _dirty = true;
    await save();
  }

  /// Applies [mutate] to the in-memory task list without saving, marking
  /// the repository dirty so [saveIfDirty] (autosave on exit / Ctrl+S)
  /// persists it later. Test hook for buffered edits.
  void applyUnsaved(void Function(List<Task>) mutate) {
    _ensureLoaded();
    _pushHistory();
    mutate(_tasks);
    _dirty = true;
  }

  void _pushHistory() {
    _history.add([for (final t in _tasks) Task.fromText(t.toText())]);
  }

  void _ensureLoaded() {
    if (_path == null) throw StateError('No file loaded');
  }
}

/// Default todo.txt location:
///
/// * Linux: `~/Tasks/todo.txt`
/// * Android: `<app documents dir>/todo.txt` (app-private, always writable
///   under scoped storage; no storage permission needed).
/// * Otherwise: `Tasks/todo.txt` under [homeDir] (or current dir if empty).
///
/// [platform], [homeDir] and [storageRoot] are injectable for tests;
/// by default they come from [Platform].
/// NOTE: [storageRoot] is deprecated (shared storage is blocked by scoped
/// storage on Android 10+) and only kept for backwards compatibility.
String defaultTodoPath({String? platform, String? homeDir, String? storageRoot}) {
  final isAndroid = platform != null
      ? platform == 'android'
      : Platform.isAndroid;
  if (isAndroid) {
    final root = storageRoot ?? '/storage/emulated/0';
    return '$root/Tasks/todo.txt';
  }
  final home = homeDir ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) return '$home/Tasks/todo.txt';
  return 'Tasks/todo.txt';
}

/// Derives the shared-storage root from an app-specific external dir
/// (e.g. `/storage/emulated/10/Android/data/com.example/files` → `/storage/emulated/10`).
String storageRootFromAppDir(String appDir) {
  final idx = appDir.indexOf('/Android/data');
  if (idx <= 0) return appDir;
  return appDir.substring(0, idx);
}

/// Dynamically resolves the Android shared-storage root via
/// `getExternalStorageDirectories()` (handles multi-user, SD cards, OEM paths).
/// Falls back to `/storage/emulated/0` when unavailable.
Future<String> androidStorageRoot(
    {Future<List<Directory?>?> Function()? externalDirs}) async {
  try {
    final dirs = await (externalDirs ?? getExternalStorageDirectories)();
    for (final d in dirs ?? <Directory?>[]) {
      final p = d?.path;
      if (p != null && p.isNotEmpty) return storageRootFromAppDir(p);
    }
  } catch (_) {
    // Fall through to fallback.
  }
  return '/storage/emulated/0';
}

/// Async default path: on Android uses the app-private documents directory
/// (always writable under scoped storage), elsewhere same as [defaultTodoPath].
/// [appDocDir] / [externalDirs] are injectable for tests.
Future<String> defaultTodoPathAsync(
    {String? platform,
    String? homeDir,
    String? appDocDir,
    Future<List<Directory?>?> Function()? externalDirs}) async {
  final isAndroid =
      platform != null ? platform == 'android' : Platform.isAndroid;
  if (isAndroid) {
    try {
      final dir = appDocDir ?? (await getApplicationDocumentsDirectory()).path;
      return '$dir/todo.txt';
    } catch (_) {
      // Fall through to legacy shared-storage lookup.
    }
    final root = await androidStorageRoot(externalDirs: externalDirs);
    return '$root/Tasks/todo.txt';
  }
  return defaultTodoPath(platform: platform, homeDir: homeDir);
}

/// Resolves the todo.txt file path from command-line args.
///
/// Returns `args.first` when present, otherwise [defaultTodoPath].
/// [exists] is kept for backwards compatibility but no longer used.
String resolveTodoPath(
  List<String> args, {
  bool Function(String)? exists,
  String? platform,
  String? homeDir,
  String? storageRoot,
}) {
  if (args.isNotEmpty) return args.first;
  return defaultTodoPath(
      platform: platform, homeDir: homeDir, storageRoot: storageRoot);
}

/// Async variant: `args.first` when present, otherwise [defaultTodoPathAsync]
/// (app-private documents dir on Android).
Future<String> resolveTodoPathAsync(
  List<String> args, {
  String? platform,
  String? homeDir,
  String? appDocDir,
  Future<List<Directory?>?> Function()? externalDirs,
}) async {
  if (args.isNotEmpty) return args.first;
  return defaultTodoPathAsync(
      platform: platform,
      homeDir: homeDir,
      appDocDir: appDocDir,
      externalDirs: externalDirs);
}
