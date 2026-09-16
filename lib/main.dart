import 'package:flutter/material.dart';

import 'features/tasks/task_list_page.dart';
import 'features/tasks/task_repository.dart';

/// Entry point.
///
/// The todo.txt file path is supplied on the command line:
/// `flutter run -- path/to/todo.txt` (args[0]).
void main(List<String> args) {
  runApp(MyApp(todoPath: resolveTodoPath(args)));
}

class MyApp extends StatelessWidget {
  final String todoPath;
  final TaskRepository? repositoryOverride;

  const MyApp({super.key, this.todoPath = '', this.repositoryOverride});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'To-Dart-TXT',
      home: _Home(todoPath: todoPath, repositoryOverride: repositoryOverride),
    );
  }
}

class _Home extends StatefulWidget {
  final String todoPath;
  final TaskRepository? repositoryOverride;
  const _Home({required this.todoPath, this.repositoryOverride});

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final TaskRepository _repo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = widget.repositoryOverride ?? TaskRepository();
    if (widget.repositoryOverride != null) return;
    if (widget.todoPath.isEmpty) {
      _error = 'No todo.txt file supplied on command line.';
      return;
    }
    try {
      _repo.load(widget.todoPath);
    } catch (e) {
      _error = 'Failed to load ${widget.todoPath}: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('To-Dart-TXT')),
        body: Center(child: Text(_error!)),
      );
    }
    return TaskListPage(repository: _repo);
  }
}
