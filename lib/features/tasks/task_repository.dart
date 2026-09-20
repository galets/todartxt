import 'dart:convert';
import 'dart:io';

import 'package:todo_txt/todo_txt.dart';

/// Loads/saves tasks from the file supplied on the command line.
///
/// Wraps [TodoTxt] (stream-based load/save) so the UI stays decoupled and testable.
class TaskRepository {
  String? _path;
  List<Task> _tasks = [];
  final List<List<Task>> _history = [];

  String? get path => _path;
  List<Task> get tasks => List.unmodifiable(_tasks);
  bool get canUndo => _history.isNotEmpty;
  bool _dirty = false;

  /// True when in-memory tasks differ from the loaded file.
  bool get isDirty => _dirty;

  /// Loads tasks from [path] via `TodoTxt.load`.
  Future<void> load(String path) async {
    _path = path;
    _history.clear();
    _dirty = false;
    final file = File(path);
    if (!await file.exists()) {
      _tasks = [];
      return;
    }
    final lines = file.openRead().transform(utf8.decoder).transform(const LineSplitter());
    _tasks = await TodoTxt.load(lines);
  }

  /// Persists current tasks back to the file used for loading.
  Future<void> save() async {
    final path = _path;
    if (path == null) throw StateError('No file loaded');
    final sink = File(path).openWrite();
    try {
      await TodoTxt.save(_tasks, sink);
    } finally {
      await sink.close();
    }
    _dirty = false;
  }

  /// Saves only when there are unsaved changes (used for autosave on exit).
  Future<void> saveIfDirty() async {
    if (!_dirty) return;
    await save();
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

/// Resolves the todo.txt file path from command-line args.
///
/// Returns `args.first` when present, otherwise `todo.txt` from the
/// current directory if it exists, otherwise an empty string
/// so the UI can show a "no file supplied" state.
String resolveTodoPath(List<String> args, {bool Function(String)? exists}) {
  if (args.isNotEmpty) return args.first;
  const fallback = 'todo.txt';
  final fileExists = exists ?? ((path) => File(path).existsSync());
  return fileExists(fallback) ? fallback : '';
}
