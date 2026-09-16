import 'package:todo_txt/todo_txt.dart';

/// Loads/saves tasks from the file supplied on the command line.
///
/// Wraps [TodoTxt] so the UI stays decoupled and testable.
class TaskRepository {
  TodoTxt? _store;

  String? get path => _store?.path;
  List<Task> get tasks => List.unmodifiable(_store?.tasks ?? const []);

  /// Loads tasks from [path] via `TodoTxt.readFromFile`.
  void load(String path) {
    _store = TodoTxt.readFromFile(path: path);
  }

  /// Persists current tasks back to the file used for loading.
  void save() {
    final store = _store;
    if (store == null) throw StateError('No file loaded');
    store.writeToFile();
  }

  void toggleCompleted(int index) {
    final store = _store;
    if (store == null) throw StateError('No file loaded');
    store.tasks[index].completed = !store.tasks[index].completed;
    save();
  }

  void add(Task task) {
    final store = _store;
    if (store == null) throw StateError('No file loaded');
    store.tasks.add(task);
    save();
  }

  void update(int index, Task task) {
    final store = _store;
    if (store == null) throw StateError('No file loaded');
    store.tasks[index] = task;
    save();
  }

  void removeAt(int index) {
    final store = _store;
    if (store == null) throw StateError('No file loaded');
    store.tasks.removeAt(index);
    save();
  }
}

/// Resolves the todo.txt file path from command-line args.
///
/// Returns `args.first` when present, otherwise an empty string
/// so the UI can show a "no file supplied" state.
String resolveTodoPath(List<String> args) =>
    args.isNotEmpty ? args.first : '';
